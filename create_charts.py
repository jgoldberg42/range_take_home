from pathlib import Path
import subprocess
import sys

import matplotlib.dates as mdates
import matplotlib.pyplot as plt
import pandas as pd


PROJECT_DIR = Path(__file__).resolve().parent
DATA_DIR = PROJECT_DIR / "data"
OUTPUT_DIR = PROJECT_DIR / "outputs"
CHART_DIR = OUTPUT_DIR / "charts"
PROMOTION_LAUNCH = pd.Timestamp("2026-03-01")
DATA_CUTOFF = pd.Timestamp("2026-09-15")


def mark_promotion_launch(axis: plt.Axes) -> None:
    axis.axvspan(PROMOTION_LAUNCH, pd.Timestamp("2026-09-01"), color="#f4a261", alpha=0.12)
    axis.axvline(PROMOTION_LAUNCH, color="#c2410c", linestyle="--", linewidth=1.5)
    axis.text(
        PROMOTION_LAUNCH + pd.Timedelta(days=8),
        0.97,
        "HARBOR50 launch",
        transform=axis.get_xaxis_transform(),
        color="#9a3412",
        fontsize=9,
        va="top",
    )


def format_month_axis(axis: plt.Axes) -> None:
    axis.xaxis.set_major_locator(mdates.MonthLocator(interval=3))
    axis.xaxis.set_major_formatter(mdates.DateFormatter("%b %Y"))
    axis.grid(axis="y", color="#d8dee4", linewidth=0.7)
    axis.set_axisbelow(True)


def plot_churn() -> Path:
    churn = pd.read_csv(OUTPUT_DIR / "monthly_churn.csv", parse_dates=["month_start"])
    churn = churn[churn["plan_group"].isin(["all plans", "monthly"])].copy()
    churn = churn[churn["month_start"] < pd.Timestamp("2026-09-01")]

    fig, axis = plt.subplots(figsize=(10, 5.5), layout="constrained")
    colors = {"all plans": "#52606d", "monthly": "#087e8b"}
    labels = {"all plans": "All plans", "monthly": "Monthly plans"}
    for plan_group in ("all plans", "monthly"):
        series = churn[churn["plan_group"] == plan_group]
        axis.plot(
            series["month_start"],
            series["opening_base_churn_pct"],
            marker="o",
            markersize=4,
            linewidth=2,
            color=colors[plan_group],
            label=labels[plan_group],
        )

    mark_promotion_launch(axis)
    axis.set_title("Monthly Subscription Churn", loc="left", weight="bold", fontsize=15)
    axis.set_ylabel("Opening-base churn (%)")
    axis.set_xlabel("")
    axis.legend(frameon=False, loc="upper left")
    axis.text(
        0,
        -0.22,
        "Cancellations among subscriptions active before the first of each month; September excluded (partial data).",
        transform=axis.transAxes,
        fontsize=9,
        color="#52606d",
    )
    format_month_axis(axis)
    path = CHART_DIR / "monthly_churn.png"
    fig.savefig(path, dpi=180, facecolor="white")
    plt.close(fig)
    return path


def plot_recommendation_rate() -> Path:
    survey = pd.read_csv(DATA_DIR / "survey_responses.csv", parse_dates=["survey_date"])
    survey["recommendation"] = survey["would_recommend"].astype("string").str.strip().str.lower()
    survey = survey[survey["recommendation"].isin(["yes", "no"])].copy()
    survey["survey_quarter"] = survey["survey_date"].dt.to_period("Q").astype("string")
    summary = (
        survey.assign(is_yes=survey["recommendation"].eq("yes"))
        .groupby("survey_quarter", as_index=False)
        .agg(yes_responses=("is_yes", "sum"), valid_responses=("is_yes", "size"))
    )
    summary["yes_rate_pct"] = 100 * summary["yes_responses"] / summary["valid_responses"]
    summary.to_csv(OUTPUT_DIR / "quarterly_survey_recommendation.csv", index=False)

    fig, axis = plt.subplots(figsize=(10, 5.5), layout="constrained")
    positions = range(len(summary))
    bars = axis.bar(
        positions,
        summary["yes_rate_pct"],
        width=0.58,
        color="#087e8b",
        edgecolor="white",
    )
    for bar, yes_count, count in zip(
        bars,
        summary["yes_responses"],
        summary["valid_responses"],
        strict=True,
    ):
        axis.annotate(
            f"{yes_count}/{count} yes",
            (bar.get_x() + bar.get_width() / 2, bar.get_height()),
            xytext=(0, 5),
            textcoords="offset points",
            ha="center",
            fontsize=9,
            color="#52606d",
        )

    axis.set_ylim(0, 110)
    axis.set_title("Would Recommend: Yes Rate by Quarter", loc="left", weight="bold", fontsize=15)
    axis.set_ylabel("Yes responses (% of valid yes/no responses)")
    axis.set_xlabel("")
    axis.grid(axis="y", color="#d8dee4", linewidth=0.7)
    axis.set_axisbelow(True)
    axis.set_xticks(list(positions), summary["survey_quarter"])
    axis.text(
        0,
        -0.22,
        "Quarterly survey waves (responses recorded mid-quarter); rates describe respondents, not all subscribers.",
        transform=axis.transAxes,
        fontsize=9,
        color="#52606d",
    )
    path = CHART_DIR / "quarterly_recommendation_rate.png"
    fig.savefig(path, dpi=180, facecolor="white")
    plt.close(fig)
    return path


def plot_new_subscriptions() -> Path:
    starts = pd.read_csv(OUTPUT_DIR / "monthly_subscription_starts.csv", parse_dates=["month_start"])
    starts = starts[starts["month_start"] < pd.Timestamp("2026-09-01")].copy()
    starts["monthly_without_harbor50"] = (
        starts["monthly_new_subscriptions"] - starts["harbor50_monthly_starts"]
    )

    fig, axis = plt.subplots(figsize=(10, 5.5), layout="constrained")
    width = 20
    axis.bar(
        starts["month_start"],
        starts["monthly_without_harbor50"],
        width=width,
        color="#087e8b",
        label="Monthly, without HARBOR50 code",
    )
    axis.bar(
        starts["month_start"],
        starts["harbor50_monthly_starts"],
        width=width,
        bottom=starts["monthly_without_harbor50"],
        color="#e76f51",
        label="Monthly, HARBOR50 code",
    )
    axis.bar(
        starts["month_start"],
        starts["annual_new_subscriptions"],
        width=width,
        bottom=starts["monthly_new_subscriptions"],
        color="#9aa5b1",
        label="Annual",
    )
    axis.bar(
        starts["month_start"],
        starts["other_plan_new_subscriptions"],
        width=width,
        bottom=starts["monthly_new_subscriptions"] + starts["annual_new_subscriptions"],
        color="#d8dee4",
        label="Other plans",
    )

    mark_promotion_launch(axis)
    axis.set_title("New Subscription Starts by Month", loc="left", weight="bold", fontsize=15)
    axis.set_ylabel("New subscriptions")
    axis.set_xlabel("")
    axis.legend(frameon=False, ncol=2, loc="upper left")
    axis.text(
        0,
        -0.22,
        "Counts are subscription starts, not unique customers; HARBOR50 is identified by discount code.",
        transform=axis.transAxes,
        fontsize=9,
        color="#52606d",
    )
    format_month_axis(axis)
    path = CHART_DIR / "new_subscriptions_by_month.png"
    fig.savefig(path, dpi=180, facecolor="white")
    plt.close(fig)
    return path


def main() -> None:
    subprocess.run(
        [sys.executable, str(PROJECT_DIR / "run_analysis.py")],
        cwd=PROJECT_DIR,
        check=True,
    )
    CHART_DIR.mkdir(parents=True, exist_ok=True)
    chart_paths = [plot_churn(), plot_recommendation_rate(), plot_new_subscriptions()]
    for chart_path in chart_paths:
        print(f"Created {chart_path.relative_to(PROJECT_DIR)}")


if __name__ == "__main__":
    main()