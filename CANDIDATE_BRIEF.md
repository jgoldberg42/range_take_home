# Harbor Analyst Take-Home

**Harbor** is a subscription personal finance membership that offers $59/month or $588/year. On March 1, 2026 it launched a promotion called **HARBOR50** that provides 50% off the first 3 months of a monthly plan.  It was promoted through paid social ads.

## The ask

You've just joined Harbor's data team. This email is waiting for you:

> **From:** Dana Whitfield, VP Operations  
> **Subject:** churn — need your read before Thursday
>
> In the June board deck we reported monthly churn of **2.7%**. Finance just closed August at **5%**, and the CEO is alarmed. The head of marketing says finance is measuring it wrong and the retention dashboard shows our newest members are canceling less than older ones. Our CFO thinks HARBOR50 is bringing in poor quality customers and wants to cancel it at month end.
>
> Can you find out if our retention is actually getting worse, and what should we do about it?
> — Dana

Since you can't ask Dana direct questions, please include any assumptions you made and any clarifying questions you would have asked.

## The data

Four CSVs in `data/`, exported **September 15, 2026**.

| File | Grain |
| --- | --- |
| `customers.csv` | one row per customer (signup date, channel, demographics) |
| `subscriptions.csv` | one row per subscription (plan, price, discount code, start/cancel, status) |
| `survey_responses.csv` | one row per satisfaction survey response (0–10) |
| `marketing_spend.csv` | one row per channel-month of ad spend |

## Deliverables

1. **A brief memo for Dana.**
2. **An appendix**: supporting analysis, data-quality notes, assumptions, questions for Dana.
3. **Your work** — SQL, Python, R, notebook, or BI tool. Only requirement: we can retrace every memo number from the raw CSVs. (BI tools: include the SQL/field definitions, not just screenshots.)

## AI

You are allowed and expected to use AI.  In the appendix, say briefly how you used it and what you checked.
