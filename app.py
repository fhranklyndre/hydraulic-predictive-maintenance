
import streamlit as st
import pandas as pd

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
    predictions = pd.read_csv("data/ml_predictions_for_powerbi_corrected.csv")
    model_results = pd.read_csv("data/combined_model_performance_results.csv")

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

predictions, model_results = load_data()

machine_col = find_col(predictions, ["machine_id", "Machine ID"])
timestamp_col = find_col(predictions, ["timestamp", "reading_timestamp", "Prediction Date"])
critical_prob_col = find_col(
    predictions,
    ["predicted_critical_probability", "predicted_critical_prob", "Critical Probability"]
)
rul_col = find_col(predictions, ["rul_hours", "actual_rul_hours"])
pred_rul_col = find_col(predictions, ["predicted_rul_hours"])

predictions[rul_col] = pd.to_numeric(predictions[rul_col], errors="coerce")

if critical_prob_col:
    predictions[critical_prob_col] = pd.to_numeric(predictions[critical_prob_col], errors="coerce")

if pred_rul_col:
    predictions[pred_rul_col] = pd.to_numeric(predictions[pred_rul_col], errors="coerce")

if timestamp_col:
    predictions[timestamp_col] = pd.to_datetime(predictions[timestamp_col], errors="coerce")

# Machine-level RUL rule.
# This controls the top KPI summary.
# 0-24 hours = Critical
# 25-499 hours = Warning
# 500 hours = Stable
machine_summary_rul_map = predictions.groupby(machine_col)[rul_col].max()

predictions["machine_summary_rul"] = predictions[machine_col].map(machine_summary_rul_map)

predictions["dashboard_final_critical_status"] = predictions["machine_summary_rul"].apply(assign_critical_status)
predictions["dashboard_final_rul_risk"] = predictions["machine_summary_rul"].apply(assign_rul_risk)
predictions["dashboard_recommended_action"] = predictions["machine_summary_rul"].apply(assign_action)

# Row-level RUL risk.
# This is used only for the risk distribution chart.
predictions["row_level_rul_risk"] = predictions[rul_col].apply(assign_rul_risk)

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

display_df = display_df.rename(
    columns={
        "dashboard_final_critical_status": "final_critical_status",
        "dashboard_final_rul_risk": "final_rul_risk",
        "dashboard_recommended_action": "final_recommended_action"
    }
)

st.dataframe(
    display_df.head(100),
    use_container_width=True
)

st.subheader("Predicted Risk Distribution")

risk_counts_display = (
    machine_df["row_level_rul_risk"]
    .value_counts()
    .reindex(["Critical", "Warning", "Stable"], fill_value=0)
    .reset_index()
)

risk_counts_display.columns = ["Risk Class", "Record Count"]

st.bar_chart(
    risk_counts_display.set_index("Risk Class")
)

st.subheader("Selected Machine Prediction Quality")

record_count = len(machine_df)

if critical_prob_col and critical_prob_col in machine_df.columns:
    avg_raw_score = machine_df[critical_prob_col].mean()
else:
    avg_raw_score = None

if rul_col and pred_rul_col and rul_col in machine_df.columns and pred_rul_col in machine_df.columns:
    machine_df["rul_absolute_error_display"] = (
        machine_df[rul_col] - machine_df[pred_rul_col]
    ).abs()

    avg_rul_error = machine_df["rul_absolute_error_display"].mean()
else:
    avg_rul_error = None

critical_records = (
    machine_df["row_level_rul_risk"].eq("Critical").sum()
    if "row_level_rul_risk" in machine_df.columns
    else 0
)

warning_records = (
    machine_df["row_level_rul_risk"].eq("Warning").sum()
    if "row_level_rul_risk" in machine_df.columns
    else 0
)

stable_records = (
    machine_df["row_level_rul_risk"].eq("Stable").sum()
    if "row_level_rul_risk" in machine_df.columns
    else 0
)

q1, q2, q3, q4, q5 = st.columns(5)

with q1:
    st.metric("Prediction Records", f"{record_count:,}")

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

st.caption(
    "This section changes with the selected machine. It summarises prediction volume, "
    "average raw critical score, RUL prediction error, and warning/critical record counts."
)

st.subheader("Overall Model Performance Summary")

st.caption(
    "These metrics are calculated across the full test dataset and do not change when a machine is selected."
)

st.dataframe(
    model_results,
    use_container_width=True
)

st.caption(
    "This Streamlit prototype uses a machine-level RUL rule for final decisions: "
    "0-24 hours is Critical, 25-499 hours is Warning, and 500 hours is Stable. "
    "The risk distribution chart uses row-level RUL risk to show how prediction records "
    "are distributed across Critical, Warning, and Stable states."
)
