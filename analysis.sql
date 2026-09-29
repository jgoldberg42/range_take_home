CREATE OR REPLACE TEMP TABLE customers AS
SELECT *
FROM read_csv_auto('data/customers.csv', header = true, nullstr = '');

CREATE OR REPLACE TEMP TABLE subscriptions AS
SELECT
    subscription_id,
    customer_id,
    plan,
    CAST(list_price_usd AS DOUBLE) AS list_price_usd,
    discount_code,
    CAST(start_date AS DATE) AS start_date,
    CAST(cancel_date AS DATE) AS cancel_date,
    status
FROM read_csv_auto('data/subscriptions.csv', header = true, nullstr = '');

CREATE OR REPLACE TEMP TABLE marketing_spend AS
SELECT
    STRPTIME(month, '%Y-%m')::DATE AS month_start,
    channel,
    CAST(spend_usd AS DOUBLE) AS spend_usd,
    CASE
        WHEN LOWER(TRIM(channel)) = 'meta ads' THEN 'Paid social'
        WHEN LOWER(TRIM(channel)) = 'google search ads' THEN 'Paid search'
        WHEN LOWER(TRIM(channel)) = 'podcast sponsorships' THEN 'Podcast'
        WHEN LOWER(TRIM(channel)) = 'referral rewards' THEN 'Referral'
        ELSE TRIM(channel)
    END AS channel_group
FROM read_csv_auto('data/marketing_spend.csv', header = true, nullstr = '');

CREATE OR REPLACE TEMP TABLE subscription_detail AS
SELECT
    joined.*,
    CASE
        WHEN UPPER(TRIM(COALESCE(discount_code, ''))) = 'HARBOR50' THEN 'Confirmed HARBOR50'
        WHEN UPPER(TRIM(COALESCE(discount_code, ''))) = 'COMP100' THEN 'Complimentary COMP100'
        WHEN plan = 'monthly'
             AND start_date >= DATE '2026-03-01'
             AND acquisition_channel_group = 'Paid social'
             AND discount_code IS NULL THEN 'Likely paid-social campaign'
        WHEN plan = 'monthly' AND start_date >= DATE '2026-03-01' THEN 'Other post-launch monthly'
        ELSE 'Outside post-launch monthly'
    END AS promotion_group
FROM (
    SELECT
        s.*,
        c.signup_date,
        c.acquisition_channel,
        c.age_band,
        c.region,
        CASE
            WHEN c.acquisition_channel IS NULL OR TRIM(c.acquisition_channel) = '' THEN 'Unknown'
            WHEN LOWER(TRIM(c.acquisition_channel)) IN ('paid_social', 'facebook ads', 'meta ads') THEN 'Paid social'
            WHEN LOWER(TRIM(c.acquisition_channel)) IN ('paid_search', 'google ads', 'google search ads') THEN 'Paid search'
            WHEN LOWER(TRIM(c.acquisition_channel)) IN ('organic', 'organic_search') THEN 'Organic'
            WHEN LOWER(TRIM(c.acquisition_channel)) IN ('podcast', 'podcast sponsorships') THEN 'Podcast'
            WHEN LOWER(TRIM(c.acquisition_channel)) IN ('referral', 'referral program') THEN 'Referral'
            ELSE TRIM(c.acquisition_channel)
        END AS acquisition_channel_group
    FROM subscriptions AS s
    LEFT JOIN customers AS c USING (customer_id)
) AS joined;

COPY (
    SELECT 'customer_rows' AS check_name, COUNT(*)::VARCHAR AS check_value FROM customers
    UNION ALL
    SELECT 'subscription_rows', COUNT(*)::VARCHAR FROM subscriptions
    UNION ALL
    SELECT 'duplicate_customer_ids', COUNT(*)::VARCHAR
    FROM (
        SELECT customer_id FROM customers GROUP BY customer_id HAVING COUNT(*) > 1
    ) AS duplicates
    UNION ALL
    SELECT 'duplicate_subscription_ids', COUNT(*)::VARCHAR
    FROM (
        SELECT subscription_id FROM subscriptions GROUP BY subscription_id HAVING COUNT(*) > 1
    ) AS duplicates
    UNION ALL
    SELECT 'subscriptions_without_customer_match', COUNT(*)::VARCHAR
    FROM subscription_detail WHERE signup_date IS NULL
    UNION ALL
    SELECT 'subscriptions_missing_start_date', COUNT(*)::VARCHAR
    FROM subscriptions WHERE start_date IS NULL
    UNION ALL
    SELECT 'cancellations_before_start', COUNT(*)::VARCHAR
    FROM subscriptions WHERE cancel_date < start_date
    UNION ALL
    SELECT 'status_cancel_date_mismatch', COUNT(*)::VARCHAR
    FROM subscriptions
    WHERE (LOWER(status) = 'active' AND cancel_date IS NOT NULL)
       OR (LOWER(status) = 'canceled' AND cancel_date IS NULL)
    UNION ALL
    SELECT 'active_status_with_cancel_date', COUNT(*)::VARCHAR
    FROM subscriptions WHERE LOWER(status) = 'active' AND cancel_date IS NOT NULL
    UNION ALL
    SELECT 'canceled_status_without_cancel_date', COUNT(*)::VARCHAR
    FROM subscriptions WHERE LOWER(status) = 'canceled' AND cancel_date IS NULL
    UNION ALL
    SELECT 'customers_missing_channel', COUNT(*)::VARCHAR
    FROM customers WHERE acquisition_channel IS NULL OR TRIM(acquisition_channel) = ''
    UNION ALL
    SELECT 'multiple_subscriptions_per_customer', COUNT(*)::VARCHAR
    FROM (
        SELECT customer_id FROM subscriptions GROUP BY customer_id HAVING COUNT(*) > 1
    ) AS multiple_subscriptions
) TO 'outputs/data_quality.csv' (HEADER, DELIMITER ',');

COPY (
        SELECT
                DATE_TRUNC('month', start_date)::DATE AS month_start,
                COUNT(*) AS total_new_subscriptions,
                COUNT(*) FILTER (WHERE plan = 'monthly') AS monthly_new_subscriptions,
                COUNT(*) FILTER (WHERE plan = 'annual') AS annual_new_subscriptions,
                COUNT(*) FILTER (WHERE plan NOT IN ('monthly', 'annual')) AS other_plan_new_subscriptions,
                COUNT(*) FILTER (
                        WHERE plan = 'monthly'
                            AND UPPER(TRIM(COALESCE(discount_code, ''))) = 'COMP100'
                ) AS comp100_monthly_starts,
                COUNT(*) FILTER (
                        WHERE plan = 'monthly'
                            AND UPPER(TRIM(COALESCE(discount_code, ''))) = 'HARBOR50'
                ) AS harbor50_monthly_starts
        FROM subscriptions
        WHERE start_date >= DATE '2025-02-01'
            AND start_date < DATE '2026-09-01'
        GROUP BY month_start
        ORDER BY month_start
) TO 'outputs/monthly_subscription_starts.csv' (HEADER, DELIMITER ',');

    COPY (
        WITH starts AS (
            SELECT
                DATE_PART('year', start_date)::INTEGER AS start_year,
                DATE_PART('month', start_date)::INTEGER AS calendar_month,
                COUNT(*) AS monthly_starts,
                COUNT(*) FILTER (WHERE acquisition_channel_group = 'Paid social') AS paid_social_starts,
                COUNT(*) FILTER (WHERE promotion_group = 'Confirmed HARBOR50') AS confirmed_harbor50_starts,
                COUNT(*) FILTER (WHERE promotion_group = 'Likely paid-social campaign') AS likely_paid_social_starts,
                COUNT(*) FILTER (WHERE promotion_group = 'Complimentary COMP100') AS comp100_monthly_starts
            FROM subscription_detail
            WHERE plan = 'monthly'
              AND DATE_PART('month', start_date) BETWEEN 3 AND 8
              AND DATE_PART('year', start_date) IN (2025, 2026)
            GROUP BY start_year, calendar_month
        )
        SELECT
            current.calendar_month,
            current.monthly_starts AS monthly_starts_2026,
            prior.monthly_starts AS monthly_starts_2025,
            current.monthly_starts - prior.monthly_starts AS total_monthly_starts_change_yoy,
            ROUND(
                100.0 * (current.monthly_starts - prior.monthly_starts)
                / NULLIF(prior.monthly_starts, 0),
                2
            ) AS total_monthly_starts_change_pct_yoy,
            current.paid_social_starts AS paid_social_starts_2026,
            prior.paid_social_starts AS paid_social_starts_2025,
            current.paid_social_starts - prior.paid_social_starts AS paid_social_starts_change_yoy,
            current.confirmed_harbor50_starts,
            current.likely_paid_social_starts,
            current.comp100_monthly_starts
        FROM starts AS current
        JOIN starts AS prior
          ON prior.calendar_month = current.calendar_month
         AND prior.start_year = 2025
        WHERE current.start_year = 2026
        ORDER BY current.calendar_month
    ) TO 'outputs/monthly_promotion_volume.csv' (HEADER, DELIMITER ',');

COPY (
    WITH months AS (
        SELECT month_start::DATE AS month_start
        FROM GENERATE_SERIES(
            DATE '2025-02-01',
            DATE '2026-08-01',
            INTERVAL '1 month'
        ) AS generated(month_start)
    ), monthly_counts AS (
        SELECT
            m.month_start,
            COALESCE(s.plan, 'all plans') AS plan_group,
            COUNT(*) FILTER (
                WHERE s.start_date < m.month_start
                                    AND (s.cancel_date IS NULL OR s.cancel_date >= m.month_start)
            ) AS opening_active_subscriptions,
            COUNT(*) FILTER (
                WHERE s.start_date < m.month_start
                                    AND s.cancel_date >= m.month_start
                  AND s.cancel_date < m.month_start + INTERVAL '1 month'
                  AND s.cancel_date >= s.start_date
            ) AS opening_subscriptions_canceled,
            COUNT(*) FILTER (
                                WHERE s.cancel_date >= m.month_start
                  AND s.cancel_date < m.month_start + INTERVAL '1 month'
                  AND s.cancel_date >= s.start_date
            ) AS all_cancellations_in_month
        FROM months AS m
        CROSS JOIN subscriptions AS s
        GROUP BY GROUPING SETS ((m.month_start, s.plan), (m.month_start))
    )
    SELECT
        month_start,
        plan_group,
        opening_active_subscriptions,
        opening_subscriptions_canceled,
        all_cancellations_in_month,
        ROUND(
            100.0 * opening_subscriptions_canceled
            / NULLIF(opening_active_subscriptions, 0),
            2
        ) AS opening_base_churn_pct,
        ROUND(
            100.0 * all_cancellations_in_month
            / NULLIF(opening_active_subscriptions, 0),
            2
        ) AS all_cancellations_vs_opening_pct
    FROM monthly_counts
    ORDER BY month_start, plan_group
) TO 'outputs/monthly_churn.csv' (HEADER, DELIMITER ',');

COPY (
    WITH months AS (
        SELECT month_start::DATE AS month_start
        FROM (VALUES (DATE '2026-06-01'), (DATE '2026-08-01')) AS values_table(month_start)
    ), counts AS (
        SELECT
            m.month_start,
            COALESCE(s.plan, 'all plans') AS plan_group,
            COUNT(*) FILTER (
                WHERE s.start_date < m.month_start
                  AND (s.cancel_date IS NULL OR s.cancel_date >= m.month_start)
            ) AS opening_active_including_comp100,
            COUNT(*) FILTER (
                WHERE s.start_date < m.month_start
                  AND (s.cancel_date IS NULL OR s.cancel_date >= m.month_start)
                  AND UPPER(TRIM(COALESCE(s.discount_code, ''))) <> 'COMP100'
            ) AS opening_active_excluding_comp100,
            COUNT(*) FILTER (
                WHERE s.start_date < m.month_start
                  AND s.cancel_date >= m.month_start
                  AND s.cancel_date < m.month_start + INTERVAL '1 month'
                  AND s.cancel_date >= s.start_date
            ) AS opening_cancellations_including_comp100,
            COUNT(*) FILTER (
                WHERE s.start_date < m.month_start
                  AND s.cancel_date >= m.month_start
                  AND s.cancel_date < m.month_start + INTERVAL '1 month'
                  AND s.cancel_date >= s.start_date
                  AND UPPER(TRIM(COALESCE(s.discount_code, ''))) <> 'COMP100'
            ) AS opening_cancellations_excluding_comp100,
            COUNT(*) FILTER (
                WHERE s.start_date < m.month_start
                  AND (s.cancel_date IS NULL OR s.cancel_date >= m.month_start)
                  AND UPPER(TRIM(COALESCE(s.discount_code, ''))) = 'COMP100'
            ) AS comp100_opening_subscriptions
        FROM months AS m
        CROSS JOIN subscriptions AS s
        GROUP BY GROUPING SETS ((m.month_start, s.plan), (m.month_start))
    )
    SELECT
        month_start,
        plan_group,
        opening_active_including_comp100,
        opening_cancellations_including_comp100,
        ROUND(
            100.0 * opening_cancellations_including_comp100
            / NULLIF(opening_active_including_comp100, 0),
            2
        ) AS churn_including_comp100_pct,
        comp100_opening_subscriptions,
        opening_active_excluding_comp100,
        opening_cancellations_excluding_comp100,
        ROUND(
            100.0 * opening_cancellations_excluding_comp100
            / NULLIF(opening_active_excluding_comp100, 0),
            2
        ) AS churn_excluding_comp100_pct,
        ROUND(
            100.0 * opening_cancellations_including_comp100
            / NULLIF(opening_active_including_comp100, 0)
            - 100.0 * opening_cancellations_excluding_comp100
            / NULLIF(opening_active_excluding_comp100, 0),
            2
        ) AS comp100_impact_percentage_points
    FROM counts
    ORDER BY month_start, plan_group
) TO 'outputs/comp100_churn_sensitivity.csv' (HEADER, DELIMITER ',');

COPY (
    WITH segment_subscriptions AS (
        SELECT
            'age_band' AS segment_dimension,
            COALESCE(age_band, 'Unknown') AS segment_value,
            plan,
            discount_code,
            start_date,
            cancel_date
        FROM subscription_detail
        UNION ALL
        SELECT
            'region' AS segment_dimension,
            COALESCE(region, 'Unknown') AS segment_value,
            plan,
            discount_code,
            start_date,
            cancel_date
        FROM subscription_detail
    ), counts AS (
        SELECT
            segment_dimension,
            segment_value,
            COUNT(*) FILTER (
                WHERE start_date < DATE '2026-06-01'
                  AND (cancel_date IS NULL OR cancel_date >= DATE '2026-06-01')
            ) AS june_opening_subscriptions,
            COUNT(*) FILTER (
                WHERE start_date < DATE '2026-06-01'
                  AND cancel_date >= DATE '2026-06-01'
                  AND cancel_date < DATE '2026-07-01'
                  AND cancel_date >= start_date
            ) AS june_cancellations,
            COUNT(*) FILTER (
                WHERE start_date < DATE '2026-08-01'
                  AND (cancel_date IS NULL OR cancel_date >= DATE '2026-08-01')
            ) AS august_opening_subscriptions,
            COUNT(*) FILTER (
                WHERE start_date < DATE '2026-08-01'
                  AND cancel_date >= DATE '2026-08-01'
                  AND cancel_date < DATE '2026-09-01'
                  AND cancel_date >= start_date
            ) AS august_cancellations
        FROM segment_subscriptions
        WHERE plan = 'monthly'
          AND UPPER(TRIM(COALESCE(discount_code, ''))) <> 'COMP100'
        GROUP BY segment_dimension, segment_value
    )
    SELECT
        segment_dimension,
        segment_value,
        june_opening_subscriptions,
        june_cancellations,
        ROUND(100.0 * june_cancellations / NULLIF(june_opening_subscriptions, 0), 2)
            AS june_churn_pct,
        august_opening_subscriptions,
        august_cancellations,
        ROUND(100.0 * august_cancellations / NULLIF(august_opening_subscriptions, 0), 2)
            AS august_churn_pct,
        ROUND(
            100.0 * august_cancellations / NULLIF(august_opening_subscriptions, 0)
            - 100.0 * june_cancellations / NULLIF(june_opening_subscriptions, 0),
            2
        ) AS churn_change_percentage_points
    FROM counts
    ORDER BY segment_dimension, segment_value
) TO 'outputs/churn_by_age_region.csv' (HEADER, DELIMITER ',');

COPY (
    WITH checkpoints AS (
        SELECT * FROM (VALUES (30), (60), (90)) AS days(tenure_days)
    ), eligible AS (
        SELECT
            DATE_TRUNC('month', d.start_date)::DATE AS start_month,
            c.tenure_days,
            d.cancel_date,
            d.start_date + c.tenure_days * INTERVAL '1 day' AS checkpoint_date
        FROM subscription_detail AS d
        CROSS JOIN checkpoints AS c
                WHERE d.start_date IS NOT NULL
                    AND (d.cancel_date IS NULL OR d.cancel_date >= d.start_date)
                    AND DATE_TRUNC('month', d.start_date)
                            + INTERVAL '1 month' - INTERVAL '1 day'
                            + c.tenure_days * INTERVAL '1 day' <= DATE '2026-09-15'
    )
    SELECT
        start_month,
        tenure_days,
        COUNT(*) AS eligible_subscriptions,
        COUNT(*) FILTER (
            WHERE cancel_date IS NULL OR cancel_date > checkpoint_date
        ) AS retained_subscriptions,
        ROUND(
            100.0 * COUNT(*) FILTER (
                WHERE cancel_date IS NULL OR cancel_date > checkpoint_date
            ) / NULLIF(COUNT(*), 0),
            2
        ) AS retention_pct
    FROM eligible
    GROUP BY start_month, tenure_days
    ORDER BY start_month, tenure_days
) TO 'outputs/cohort_retention.csv' (HEADER, DELIMITER ',');

COPY (
    WITH checkpoints AS (
        SELECT * FROM (VALUES (30), (60), (90)) AS days(tenure_days)
    ), eligible AS (
        SELECT
            DATE_TRUNC('month', d.start_date)::DATE AS start_month,
            d.acquisition_channel_group,
            d.promotion_group,
            c.tenure_days,
            d.cancel_date,
            d.start_date + c.tenure_days * INTERVAL '1 day' AS checkpoint_date
        FROM subscription_detail AS d
        CROSS JOIN checkpoints AS c
        WHERE d.plan = 'monthly'
          AND d.start_date >= DATE '2026-03-01'
                    AND (d.cancel_date IS NULL OR d.cancel_date >= d.start_date)
                    AND DATE_TRUNC('month', d.start_date)
                            + INTERVAL '1 month' - INTERVAL '1 day'
                            + c.tenure_days * INTERVAL '1 day' <= DATE '2026-09-15'
    )
    SELECT
        start_month,
        CASE
            WHEN GROUPING(acquisition_channel_group) = 1 THEN 'All channels'
            ELSE acquisition_channel_group
        END AS acquisition_channel_group,
        promotion_group,
        tenure_days,
        COUNT(*) AS eligible_subscriptions,
        COUNT(*) FILTER (
            WHERE cancel_date IS NULL OR cancel_date > checkpoint_date
        ) AS retained_subscriptions,
        ROUND(
            100.0 * COUNT(*) FILTER (
                WHERE cancel_date IS NULL OR cancel_date > checkpoint_date
            ) / NULLIF(COUNT(*), 0),
            2
        ) AS retention_pct
    FROM eligible
    GROUP BY GROUPING SETS (
        (start_month, acquisition_channel_group, promotion_group, tenure_days),
        (start_month, promotion_group, tenure_days)
    )
    ORDER BY start_month, acquisition_channel_group, promotion_group, tenure_days
) TO 'outputs/promotion_retention.csv' (HEADER, DELIMITER ',');

COPY (
    WITH checkpoints AS (
        SELECT * FROM (VALUES (30), (60), (90)) AS days(tenure_days)
    ), eligible AS (
        SELECT
            DATE_TRUNC('month', d.start_date)::DATE AS start_month,
            d.acquisition_channel_group,
            c.tenure_days,
            d.cancel_date,
            d.start_date + c.tenure_days * INTERVAL '1 day' AS checkpoint_date
        FROM subscription_detail AS d
        CROSS JOIN checkpoints AS c
        WHERE d.plan = 'monthly'
          AND DATE_PART('month', d.start_date) BETWEEN 3 AND 8
          AND DATE_PART('year', d.start_date) IN (2025, 2026)
          AND (d.cancel_date IS NULL OR d.cancel_date >= d.start_date)
          AND DATE_TRUNC('month', d.start_date)
              + INTERVAL '1 month' - INTERVAL '1 day'
              + c.tenure_days * INTERVAL '1 day' <= DATE '2026-09-15'
    )
    SELECT
        start_month,
        DATE_PART('year', start_month)::INTEGER AS cohort_year,
        DATE_PART('month', start_month)::INTEGER AS cohort_calendar_month,
        CASE
            WHEN GROUPING(acquisition_channel_group) = 1 THEN 'All channels'
            ELSE acquisition_channel_group
        END AS acquisition_channel_group,
        tenure_days,
        COUNT(*) AS eligible_subscriptions,
        COUNT(*) FILTER (
            WHERE cancel_date IS NULL OR cancel_date > checkpoint_date
        ) AS retained_subscriptions,
        ROUND(
            100.0 * COUNT(*) FILTER (
                WHERE cancel_date IS NULL OR cancel_date > checkpoint_date
            ) / NULLIF(COUNT(*), 0),
            2
        ) AS retention_pct
    FROM eligible
    GROUP BY GROUPING SETS (
        (start_month, cohort_year, cohort_calendar_month, acquisition_channel_group, tenure_days),
        (start_month, cohort_year, cohort_calendar_month, tenure_days)
    )
    ORDER BY cohort_calendar_month, acquisition_channel_group, tenure_days, cohort_year
) TO 'outputs/year_over_year_retention.csv' (HEADER, DELIMITER ',');

COPY (
    WITH eligible AS (
        SELECT
            DATE_TRUNC('month', d.start_date)::DATE AS start_month,
            d.acquisition_channel_group,
            d.promotion_group,
            d.cancel_date,
            (d.start_date + INTERVAL '3 months')::DATE AS promotion_end_date,
            exposure_window.window_label,
            exposure_window.window_start,
            exposure_window.window_end
        FROM subscription_detail AS d
        CROSS JOIN LATERAL (
            VALUES
                ('30d_before_expiry', (d.start_date + INTERVAL '3 months' - INTERVAL '30 days')::DATE,
                    (d.start_date + INTERVAL '3 months')::DATE),
                ('0_30d_after_expiry', (d.start_date + INTERVAL '3 months')::DATE,
                    (d.start_date + INTERVAL '3 months' + INTERVAL '30 days')::DATE),
                ('31_60d_after_expiry', (d.start_date + INTERVAL '3 months' + INTERVAL '30 days')::DATE,
                    (d.start_date + INTERVAL '3 months' + INTERVAL '60 days')::DATE),
                ('61_90d_after_expiry', (d.start_date + INTERVAL '3 months' + INTERVAL '60 days')::DATE,
                    (d.start_date + INTERVAL '3 months' + INTERVAL '90 days')::DATE)
        ) AS exposure_window(window_label, window_start, window_end)
        WHERE d.plan = 'monthly'
          AND d.start_date >= DATE '2026-03-01'
          AND d.promotion_group IN (
              'Confirmed HARBOR50',
              'Likely paid-social campaign',
              'Other post-launch monthly'
          )
          AND (d.cancel_date IS NULL OR d.cancel_date >= d.start_date)
          AND exposure_window.window_end <= DATE '2026-09-15'
    )
    SELECT
        start_month,
        CASE
            WHEN GROUPING(acquisition_channel_group) = 1 THEN 'All channels'
            ELSE acquisition_channel_group
        END AS acquisition_channel_group,
        promotion_group,
        window_label,
        MIN(window_start) AS first_window_start,
        MAX(window_end) AS last_window_end,
        COUNT(*) FILTER (
            WHERE cancel_date IS NULL OR cancel_date >= window_start
        ) AS at_risk_subscriptions,
        COUNT(*) FILTER (
            WHERE cancel_date >= window_start AND cancel_date < window_end
        ) AS cancellations_in_window,
        ROUND(
            100.0 * COUNT(*) FILTER (
                WHERE cancel_date >= window_start AND cancel_date < window_end
            ) / NULLIF(COUNT(*) FILTER (
                WHERE cancel_date IS NULL OR cancel_date >= window_start
            ), 0),
            2
        ) AS conditional_cancellation_pct
    FROM eligible
    GROUP BY GROUPING SETS (
        (start_month, acquisition_channel_group, promotion_group, window_label),
        (start_month, promotion_group, window_label)
    )
    ORDER BY start_month, acquisition_channel_group, promotion_group, window_label
) TO 'outputs/post_promotion_cancellations.csv' (HEADER, DELIMITER ',');

COPY (
        WITH subscription_starts AS (
                SELECT
                        DATE_TRUNC('month', start_date)::DATE AS month_start,
                        acquisition_channel_group AS channel_group,
                        COUNT(*) AS monthly_subscription_starts,
                        COUNT(*) FILTER (WHERE promotion_group = 'Confirmed HARBOR50')
                                AS confirmed_harbor50_starts,
                        COUNT(*) FILTER (WHERE promotion_group = 'Likely paid-social campaign')
                                AS likely_paid_social_starts
                FROM subscription_detail
                WHERE start_date >= DATE '2026-03-01'
                    AND plan = 'monthly'
                GROUP BY month_start, channel_group
        )
        SELECT
                STRFTIME(m.month_start, '%Y-%m') AS month,
                m.channel,
                m.channel_group,
                m.spend_usd AS total_channel_spend_usd,
                COALESCE(s.monthly_subscription_starts, 0) AS monthly_subscription_starts,
                COALESCE(s.confirmed_harbor50_starts, 0) AS confirmed_harbor50_starts,
                COALESCE(s.likely_paid_social_starts, 0) AS likely_paid_social_starts
        FROM marketing_spend AS m
        LEFT JOIN subscription_starts AS s
            ON m.month_start = s.month_start
         AND m.channel_group = s.channel_group
        WHERE m.month_start >= DATE '2026-03-01'
            AND m.month_start < DATE '2026-09-01'
        ORDER BY m.month_start, m.channel
) TO 'outputs/marketing_spend_context.csv' (HEADER, DELIMITER ',');

COPY (
    WITH scenarios AS (
        SELECT * FROM (VALUES (0.03), (0.05), (0.08)) AS churn_rates(monthly_churn_rate)
    ), invoice_schedule AS (
        SELECT
            monthly_churn_rate,
            invoice_month,
            POWER(1 - monthly_churn_rate, invoice_month) AS expected_invoice_probability
        FROM scenarios
        CROSS JOIN GENERATE_SERIES(0, 14) AS months(invoice_month)
    ), estimates AS (
        SELECT
            monthly_churn_rate,
            SUM(expected_invoice_probability) FILTER (WHERE invoice_month BETWEEN 0 AND 2)
                AS expected_discounted_invoices,
            SUM(expected_invoice_probability) FILTER (WHERE invoice_month BETWEEN 3 AND 14)
                AS expected_full_price_invoices_after_promo,
            SUM(expected_invoice_probability) AS expected_full_price_invoices_without_promo
        FROM invoice_schedule
        GROUP BY monthly_churn_rate
    )
    SELECT
        monthly_churn_rate,
        59.0 AS assumed_monthly_list_price_usd,
        0.50 AS assumed_discount_rate,
        3 AS assumed_discounted_months,
        12 AS full_price_months_in_projection,
        ROUND(expected_discounted_invoices * 59.0 * 0.50, 2)
            AS projected_promo_period_revenue_usd,
        ROUND(expected_full_price_invoices_after_promo * 59.0, 2)
            AS projected_post_promo_revenue_usd,
        ROUND(
            expected_discounted_invoices * 59.0 * 0.50
            + expected_full_price_invoices_after_promo * 59.0,
            2
        ) AS projected_15_month_promo_gross_revenue_usd,
        ROUND(expected_full_price_invoices_without_promo * 59.0, 2)
            AS projected_15_month_full_price_gross_revenue_usd,
        ROUND(expected_discounted_invoices * 59.0 * 0.50, 2)
            AS projected_discount_concession_usd,
        ROUND(
            expected_full_price_invoices_after_promo * 59.0
            - expected_discounted_invoices * 59.0 * 0.50,
            2
        ) AS post_promo_revenue_less_discount_concession_usd,
        ROUND(
            expected_full_price_invoices_after_promo * 59.0
            / NULLIF(expected_discounted_invoices * 59.0 * 0.50, 0),
            2
        ) AS post_promo_revenue_to_discount_concession_ratio
    FROM estimates
    ORDER BY monthly_churn_rate
) TO 'outputs/promotion_revenue_scenarios.csv' (HEADER, DELIMITER ',');