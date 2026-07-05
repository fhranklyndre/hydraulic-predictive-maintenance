
import streamlit as st
import pandas as pd
from pathlib import Path

st.set_page_config(
    page_title="Hydraulic Predictive Maintenance App",
    layout="wide"
)

st.title("Hydraulic Predictive Maintenance Decision Support App")

st.write(
    "This prototype uses machine learning outputs to support maintenance engineers "
    "in identifying critical hydraulic units, reviewing RUL risk, and prioritising maintenance actions."
)

@st.cache_data
def load_data():
    prediction_paths = [
        "data/ml_predictions_for_powerbi_corrected.csv",
        "ml_predictions_for_powerbi_corrected.csv"
    ]

    model_result_paths = [
        "data/combined_model_performance_results.csv",
        "combined_model_performance_results.csv"
    ]

    predictions_path = next((p for p in prediction_paths if Path(p).exists()), None)
    model_results_path = next((p for p in model_result_paths if Path(p).exists()), None)

    if predictions_path is None:
        st.error("Could not find ml_predictions_for_powerbi_corrected.csv.")
        st.stop()

    if model_results_path is None:
        st.error("Could not find combined_model_performance_results.csv.")
        st.stop()

    predictions = pd.read_csv(predictions_path)
    model_results = pd.read_csv(model_results_path)

    predictions.columns = predictions.columns.str.strip()
    model_results.columns = model_results.columns.str.strip()

    return predictions, model_results

def find_col(df, possible_names):
    for name in possible_names:
        if name in df.columns:
            return name
    return None

def assign_rul_risk(rul_value):
    if pd.isna(rul_value):
        return "Unknown"
    elif rul_value <= 24:
        return "Critical"
    elif rul_value < 500:
        return "Warning"
    else:
        return "Stable"

def assign_critical_status(rul_value):
    if pd.isna(rul_value):
        return "Unknown"
    elif rul_value <= 24:
        return "Critical"
    else:
        return "Non-Critical"

def assign_action(rul_value):
    if pd.isna(rul_value):
        return "Review condition"
    elif rul_value <= 24:
        return "Inspect immediately"
    elif rul_value < 500:
        return "Monitor and schedule maintenance"
    else:
        return "Continue monitoring"

def get_metric(model_results, task, model, metric):
    row = model_results[
        (model_results["model_task"] == task) &
        (model_results["model_name"] == model)
    ]

    if row.empty or metric not in row.columns:
        return None

    value = row.iloc[0][metric]

    if pd.isna(value):
        return None

    return value

def pct(value):
    if value is None:
        return "N/A"
    return f"{value * 100:.2f}%"

def number(value, decimals=2):
    if value is None:
        return "N/A"
    return f"{value:.{decimals}f}"

predictions, model_results = load_data()

machine_col = find_col(predictions, ["machine_id", "Machine ID"])
timestamp_col = find_col(predictions, ["timestamp", "reading_timestamp", "Prediction Date"])
critical_prob_col = find_col(
    predictions,
    ["predicted_critical_probability", "predicted_critical_prob", "Critical Probability"]
)
rul_col = find_col(predictions, ["rul_hours", "actual_rul_hours"])
pred_rul_col = find_col(predictions, ["predicted_rul_hours"])

if machine_col is None or rul_col is None:
    st.error("Required columns are missing. Please check machine_id and rul_hours columns.")
    st.stop()

predictions[rul_col] = pd.to_numeric(predictions[rul_col], errors="coerce")

if critical_prob_col:
    predictions[critical_prob_col] = pd.to_numeric(predictions[critical_prob_col], errors="coerce")

if pred_rul_col:
    predictions[pred_rul_col] = pd.to_numeric(predictions[pred_rul_col], errors="coerce")

if timestamp_col:
    predictions[timestamp_col] = pd.to_datetime(predictions[timestamp_col], errors="coerce")

predictions["row_level_rul_risk"] = predictions[rul_col].apply(assign_rul_risk)

machine_summary_rul_map = predictions.groupby(machine_col)[rul_col].max()
predictions["machine_summary_rul"] = predictions[machine_col].map(machine_summary_rul_map)

predictions["dashboard_final_critical_status"] = predictions["machine_summary_rul"].apply(assign_critical_status)
predictions["dashboard_final_rul_risk"] = predictions["machine_summary_rul"].apply(assign_rul_risk)
predictions["dashboard_recommended_action"] = predictions["machine_summary_rul"].apply(assign_action)

st.sidebar.header("Filters")

machine_list = sorted(predictions[machine_col].dropna().unique())

selected_machine = st.sidebar.selectbox(
    "Select Machine",
    machine_list
)

machine_df = predictions[predictions[machine_col] == selected_machine].copy()

st.subheader(f"Machine-Level Prediction Summary: {selected_machine}")

if machine_df.empty:
    st.warning("No prediction records available for this machine.")
else:
    machine_summary_rul = machine_df["machine_summary_rul"].iloc[0]

    machine_final_status = assign_critical_status(machine_summary_rul)
    machine_summary_risk = assign_rul_risk(machine_summary_rul)
    action_value = assign_action(machine_summary_rul)

    if timestamp_col:
        summary_row = machine_df.sort_values(timestamp_col).head(1).iloc[0]
    else:
        summary_row = machine_df.head(1).iloc[0]

    col1, col2, col3, col4 = st.columns(4)

    with col1:
        st.metric("Final Critical Status", machine_final_status)

    with col2:
        st.metric("Final RUL Risk", machine_summary_risk)

    with col3:
        prob_value = summary_row.get(critical_prob_col, None) if critical_prob_col else None

        if pd.notna(prob_value):
            st.metric("Raw Critical Model Score", f"{prob_value:.4f}")
        else:
            st.metric("Raw Critical Model Score", "N/A")

    with col4:
        st.metric("Recommended Action", action_value)

st.subheader("Key Insights")

if not machine_df.empty:
    if machine_summary_risk == "Critical":
        st.error(
            f"{selected_machine} is in a Critical condition. "
            "The recommended action is to inspect immediately because the machine is close to failure."
        )
    elif machine_summary_risk == "Warning":
        st.warning(
            f"{selected_machine} is not critical yet, but it is in a Warning state. "
            "Maintenance should be planned before the machine becomes critical."
        )
    elif machine_summary_risk == "Stable":
        st.success(
            f"{selected_machine} is currently Stable. "
            "No urgent maintenance is required, but normal monitoring should continue."
        )
    else:
        st.info(
            f"{selected_machine} has an unclear risk status. "
            "The machine should be reviewed before making a maintenance decision."
        )

    st.markdown(
        """
        - **Final Critical Status** tells whether the machine needs urgent attention.
        - **Final RUL Risk** shows whether the machine is Critical, Warning, or Stable based on remaining useful life.
        - **Raw Critical Model Score** is supporting evidence from the model. A higher score means the raw model sensed stronger critical behaviour.
        - **Recommended Action** converts the risk level into a practical maintenance instruction.
        """
    )

st.subheader("Machine Prediction Records")

display_cols = [
    machine_col,
    timestamp_col,
    "dashboard_final_critical_status",
    critical_prob_col,
    rul_col,
    pred_rul_col,
    "dashboard_final_rul_risk",
    "dashboard_recommended_action"
]

available_cols = [col for col in display_cols if col is not None and col in machine_df.columns]

display_df = machine_df[available_cols].copy()

rename_cols = {
    "dashboard_final_critical_status": "final_critical_status",
    "dashboard_final_rul_risk": "final_rul_risk",
    "dashboard_recommended_action": "final_recommended_action"
}

if critical_prob_col:
    rename_cols[critical_prob_col] = "raw_critical_model_score"

if pred_rul_col:
    rename_cols[pred_rul_col] = "predicted_rul_hours"

display_df = display_df.rename(columns=rename_cols)

st.dataframe(
    display_df.head(100),
    use_container_width=True
)

with st.expander("How to read the prediction record columns"):
    st.markdown(
        """
        - **raw_critical_model_score**: how strongly the raw model thinks the machine looks critical. Closer to 1 means stronger concern.
        - **predicted_rul_hours**: the model's estimate of how many useful hours the machine may have left.
        - **rul_hours**: the actual/known remaining useful life in the dataset.
        - **final_rul_risk**: the final business risk category used for maintenance decisions.
        - **final_recommended_action**: the action the maintenance team should take.
        """
    )

st.subheader("Predicted Risk Distribution")

risk_order = ["Critical", "Warning", "Stable"]

risk_counts_display = (
    machine_df["row_level_rul_risk"]
    .value_counts()
    .reindex(risk_order, fill_value=0)
    .reset_index()
)

risk_counts_display.columns = ["Risk Class", "Record Count"]

st.bar_chart(
    risk_counts_display.set_index("Risk Class")
)

st.info(
    "This chart shows how the selected machine's prediction records are spread across Critical, "
    "Warning, and Stable risk levels. Categories with zero records are still shown so the risk profile "
    "is easy to compare across machines."
)

st.subheader("Selected Machine Prediction Quality")

prediction_records = len(machine_df)

if critical_prob_col:
    avg_raw_score = machine_df[critical_prob_col].mean()
else:
    avg_raw_score = None

if pred_rul_col:
    avg_rul_error = (machine_df[pred_rul_col] - machine_df[rul_col]).abs().mean()
else:
    avg_rul_error = None

warning_records = (machine_df["row_level_rul_risk"] == "Warning").sum()
critical_records = (machine_df["row_level_rul_risk"] == "Critical").sum()

q1, q2, q3, q4, q5 = st.columns(5)

with q1:
    st.metric("Prediction Records", f"{prediction_records:,}")

with q2:
    if avg_raw_score is not None and pd.notna(avg_raw_score):
        st.metric("Avg Raw Critical Score", f"{avg_raw_score:.4f}")
    else:
        st.metric("Avg Raw Critical Score", "N/A")

with q3:
    if avg_rul_error is not None and pd.notna(avg_rul_error):
        st.metric("Avg RUL Error", f"{avg_rul_error:.2f} hrs")
    else:
        st.metric("Avg RUL Error", "N/A")

with q4:
    st.metric("Warning Records", f"{warning_records:,}")

with q5:
    st.metric("Critical Records", f"{critical_records:,}")

st.info(
    "This section summarises the selected machine only. Prediction Records shows how many timestamped "
    "rows were reviewed. Avg Raw Critical Score shows how strongly the raw model sensed critical behaviour. "
    "Avg RUL Error shows how far the predicted remaining life was from the known value on average. "
    "Warning and Critical Records show how often the machine appeared in each risk state."
)

st.subheader("Overall Model Performance Summary")

st.info(
    "This summary compares each trained model against other models built for the same task "
    "and against a simple Dummy Baseline. The Dummy Baseline is a basic guessing model. "
    "If a real model performs much better than the Dummy Baseline, it means the model is learning "
    "useful machine behaviour patterns rather than simply guessing."
)

known_failure_accuracy = get_metric(
    model_results,
    "Known Failure Mode Classification",
    "Logistic Regression",
    "Accuracy"
)

known_failure_baseline = get_metric(
    model_results,
    "Known Failure Mode Classification",
    "Dummy Baseline",
    "Accuracy"
)

rul_mae = get_metric(
    model_results,
    "Exact RUL Regression",
    "Random Forest",
    "MAE"
)

rul_baseline_mae = get_metric(
    model_results,
    "Exact RUL Regression",
    "Dummy Baseline",
    "MAE"
)

risk_f1_macro = get_metric(
    model_results,
    "3-Class RUL Risk Classification",
    "Random Forest",
    "F1 Macro"
)

risk_baseline_f1 = get_metric(
    model_results,
    "3-Class RUL Risk Classification",
    "Dummy Baseline",
    "F1 Macro"
)

critical_recall = get_metric(
    model_results,
    "Critical vs Non-Critical Classification",
    "Logistic Regression",
    "Critical Recall"
)

critical_baseline_recall = get_metric(
    model_results,
    "Critical vs Non-Critical Classification",
    "Dummy Baseline",
    "Critical Recall"
)

friendly_model_summary = pd.DataFrame(
    [
        {
            "Model Area": "Failure Type Prediction",
            "Best Model": "Logistic Regression",
            "Compared Against": f"Dummy Baseline: {pct(known_failure_baseline)} accuracy",
            "Business Meaning": "Identifies the likely failure type, such as pump wear, valve leakage, contamination, or cylinder drift.",
            "Best Result": f"{pct(known_failure_accuracy)} accuracy",
            "Decision Insight": "Useful for helping maintenance teams understand what kind of fault is likely."
        },
        {
            "Model Area": "Remaining Useful Life Prediction",
            "Best Model": "Random Forest",
            "Compared Against": f"Dummy Baseline: {number(rul_baseline_mae)} hours average error",
            "Business Meaning": "Estimates how many useful hours a machine may have left before failure.",
            "Best Result": f"{number(rul_mae)} hours average error",
            "Decision Insight": "Useful as a planning guide, but exact RUL hours should be treated as approximate."
        },
        {
            "Model Area": "RUL Risk Grouping",
            "Best Model": "Random Forest",
            "Compared Against": f"Dummy Baseline: {pct(risk_baseline_f1)} balanced score",
            "Business Meaning": "Groups machines into Critical, Warning, or Stable risk levels.",
            "Best Result": f"{pct(risk_f1_macro)} balanced score",
            "Decision Insight": "Useful for prioritising machines into action groups."
        },
        {
            "Model Area": "Critical Risk Detection",
            "Best Model": "Logistic Regression",
            "Compared Against": f"Dummy Baseline: {pct(critical_baseline_recall)} critical cases caught",
            "Business Meaning": "Finds machines that are close to failure and need urgent attention.",
            "Best Result": f"{pct(critical_recall)} critical cases caught",
            "Decision Insight": "Useful as a safety-first alerting layer for urgent inspection."
        }
    ]
)

st.dataframe(
    friendly_model_summary,
    use_container_width=True,
    hide_index=True
)

with st.expander("How do the model tasks differ?"):
    task_explanation = pd.DataFrame(
        [
            {
                "Model Task": "Known Failure Mode Classification",
                "Plain English Meaning": "Predicts what type of fault is likely.",
                "Example Output": "pump wear, valve leakage, contamination, cylinder drift"
            },
            {
                "Model Task": "Exact RUL Regression",
                "Plain English Meaning": "Predicts the remaining useful life in hours.",
                "Example Output": "97 hours left"
            },
            {
                "Model Task": "3-Class RUL Risk Classification",
                "Plain English Meaning": "Groups the machine into a maintenance risk level.",
                "Example Output": "Critical, Warning, Stable"
            },
            {
                "Model Task": "Critical vs Non-Critical Classification",
                "Plain English Meaning": "Checks whether the machine needs urgent attention.",
                "Example Output": "Critical or Non-Critical"
            }
        ]
    )

    st.dataframe(
        task_explanation,
        use_container_width=True,
        hide_index=True
    )

with st.expander("What do these model metrics mean?"):
    st.markdown(
        """
        - **Accuracy**: how often the model gets the answer right.
        - **Precision**: when the model raises an alert, how often that alert is correct.
        - **Recall**: how good the model is at catching real problems.
        - **F1 Score**: a balanced score that combines precision and recall.
        - **MAE**: average prediction error in hours. Lower is better.
        - **RMSE**: similar to MAE, but it punishes very large errors more.
        - **R2**: shows how well the model explains exact RUL values. Higher is better.
        - **ROC AUC**: shows how well the model separates risky machines from safer machines.
        - **Dummy Baseline**: a simple guessing model used for comparison.
        """
    )

with st.expander("View technical model performance table"):
    st.dataframe(
        model_results,
        use_container_width=True
    )

st.caption(
    "This Streamlit prototype uses a machine-level RUL rule: "
    "0-24 hours is Critical, 25-499 hours is Warning, and 500 hours is Stable. "
    "The raw critical model score is shown as supporting evidence, while final maintenance decisions "
    "are based on the machine-level RUL threshold."
)
