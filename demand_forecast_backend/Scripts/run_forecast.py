import os
import sys
import warnings
import logging
import pickle
import numpy as np
import pandas as pd

# ─── Silence stdout AND stderr during imports, suppress noisy loggers ─────────
# Prophet & cmdstanpy write "Importing plotly failed" / Stan chain messages to
# both stdout and stderr.  Redirect both during import, then restore.  We also
# permanently set those loggers to ERROR so they stay quiet during model.fit().
import io as _io
_real_stdout = sys.stdout
_real_stderr  = sys.stderr
sys.stdout   = _io.StringIO()   # swallow import-time stdout
sys.stderr   = _io.StringIO()   # swallow import-time stderr

from sklearn.linear_model import LinearRegression
from statsmodels.tsa.statespace.sarimax import SARIMAX
from statsmodels.tsa.stattools import acf
from statsmodels.tsa.holtwinters import ExponentialSmoothing
from prophet import Prophet
from pmdarima import auto_arima

sys.stdout = _real_stdout   # restore
sys.stderr = _real_stderr
# ──────────────────────────────────────────────────────────────────────────────

# Permanently silence Prophet / cmdstanpy / Stan INFO messages
for _noisy in ("prophet", "cmdstanpy", "cmdstan", "pystan",
               "fbprophet", "numexpr", "matplotlib"):
    logging.getLogger(_noisy).setLevel(logging.ERROR)

warnings.filterwarnings("ignore")

# =============================
# THREAD CONTROL
# =============================
os.environ["OMP_NUM_THREADS"] = "1"
os.environ["MKL_NUM_THREADS"] = "1"

# =============================
# FILE LOADING
# =============================

def load_input_file(filepath):

    ext = os.path.splitext(filepath)[1].lower()

    if ext == ".csv":
        df = pd.read_csv(filepath)

    elif ext in [".xlsx", ".xls"]:
        df = pd.read_excel(filepath)

    elif ext == ".txt":
        df = pd.read_csv(filepath, delimiter=None, engine="python")

    else:
        raise ValueError("Unsupported file format")

    return df


# =============================
# DATA CLEANING
# =============================

def validate_and_clean(df):

    df.columns = df.columns.str.strip()

    required = ["ITEMNO", "ITEMDESC", "orderDate", "quantity"]
    for col in required:
        if col not in df.columns:
            raise ValueError(f"{col} missing")

    df["ITEMDESC"] = df["ITEMDESC"].astype(str).str.strip().str.upper()
    df["ITEMNO"] = df["ITEMNO"].astype(str).str.strip()
    df["orderDate"] = pd.to_datetime(df["orderDate"], errors="coerce", dayfirst=True)
    df["quantity"] = pd.to_numeric(df["quantity"], errors="coerce")

    df = df.dropna()
    df = df[df["quantity"] >= 0]
    df = df.drop_duplicates()

    return df.sort_values(["ITEMDESC", "ITEMNO", "orderDate"])


# =============================
# MODEL CACHE
# =============================

MODEL_CACHE_FILE = "model_cache.pkl"

def load_model_cache():
    if os.path.exists(MODEL_CACHE_FILE):
        with open(MODEL_CACHE_FILE, "rb") as f:
            return pickle.load(f)
    return {}

def save_model_cache(cache):
    with open(MODEL_CACHE_FILE, "wb") as f:
        pickle.dump(cache, f)

model_cache = load_model_cache()


# =============================
# SEASONALITY DETECTION
# =============================

def detect_seasonality(ts, m=12, threshold=0.3):

    if len(ts) < 3 * m:
        return False

    acf_values = acf(ts, nlags=m)
    return abs(acf_values[m]) > threshold


# =============================
# BUILD MONTHLY SERIES
# =============================

def build_series(group):

    monthly = (
        group
        .groupby(pd.Grouper(key="orderDate", freq="MS"))["quantity"]
        .sum()
    )

    ts = monthly.asfreq("MS").fillna(0)

    if len(ts) < 24:
        return None

    return ts


# =============================
# ARIMA ORDER SELECTION
# =============================

import hashlib

def get_arima_order(ts, sku_key):

    series_hash = hashlib.md5(ts.values.tobytes()).hexdigest()[:12]
    cache_key = f"{sku_key}_{series_hash}_{len(ts)}_order"

    if cache_key in model_cache:
        return model_cache[cache_key]

    seasonal = detect_seasonality(ts)

    try:
        model = auto_arima(
            ts,
            seasonal=seasonal,
            m=12 if seasonal else 1,
            stepwise=True,
            suppress_warnings=True,
            error_action="ignore",
            max_p=2, max_q=2,
            max_P=1, max_Q=1,
            max_d=1,
            max_D=1
        )

        order = model.order
        seasonal_order = model.seasonal_order if seasonal else (0,0,0,0)

    except Exception:
        order = (1,1,1)
        seasonal_order = (0,0,0,0)

    model_cache[cache_key] = (order, seasonal_order)
    save_model_cache(model_cache)

    return order, seasonal_order


# =============================
# FORECASTING MODELS
# =============================

def linear_forecast(ts, steps=12):

    X = np.arange(len(ts)).reshape(-1,1)
    y = ts.values

    model = LinearRegression().fit(X, y)

    future_X = np.arange(len(ts), len(ts)+steps).reshape(-1,1)
    preds = model.predict(future_X)

    return np.maximum(preds, 0)


def exp_smoothing_forecast(ts, steps=12):

    seasonal = detect_seasonality(ts)
    candidates = []

    try:
        model = ExponentialSmoothing(ts, trend=None, seasonal=None)
        fit = model.fit(optimized=True)
        candidates.append(fit)
    except:
        pass

    try:
        model = ExponentialSmoothing(ts, trend="add", seasonal=None)
        fit = model.fit(optimized=True)
        candidates.append(fit)
    except:
        pass

    if seasonal:
        try:
            model = ExponentialSmoothing(
                ts,
                trend="add",
                seasonal="add",
                seasonal_periods=12
            )
            fit = model.fit(optimized=True)
            candidates.append(fit)
        except:
            pass

    if len(candidates) == 0:
        return np.zeros(steps)

    best_model = min(candidates, key=lambda x: x.aic)
    forecast = best_model.forecast(steps)

    return np.maximum(forecast.values, 0)


def _prophet_worker(ts_index, ts_values, steps, result_queue):
    """
    Runs in a separate process so that Stan/cmdstanpy crashes (SIGABRT, exit -6)
    only kill this worker, not the main Python process.
    """
    import io as _io2
    import sys as _sys2
    import logging as _log2
    _sys2.stdout = _io2.StringIO()
    _sys2.stderr = _io2.StringIO()
    for _n in ("prophet", "cmdstanpy", "cmdstan", "fbprophet"):
        _log2.getLogger(_n).setLevel(_log2.ERROR)
    try:
        import pandas as _pd2
        import numpy as _np2
        from prophet import Prophet as _Prophet
        ts = _pd2.Series(ts_values, index=_pd2.DatetimeIndex(ts_index))
        dfp = ts.reset_index()
        dfp.columns = ["ds", "y"]
        m = _Prophet(
            yearly_seasonality=False,
            weekly_seasonality=False,
            daily_seasonality=False,
            uncertainty_samples=0,     # disables MCMC → avoids Stan sample loop crashes
        )
        m.fit(dfp)
        future = m.make_future_dataframe(periods=steps, freq="MS")
        fc = m.predict(future)
        preds = fc["yhat"].tail(steps).values
        result_queue.put(_np2.maximum(preds, 0))
    except Exception as exc:
        result_queue.put(exc)


def prophet_forecast(ts, steps=12):
    """Run Prophet in a sandboxed subprocess; fall back to ExpSmoothing on crash/timeout."""
    if len(ts) < 8:
        return exp_smoothing_forecast(ts, steps=steps)

    import multiprocessing
    ctx = multiprocessing.get_context("spawn")     # spawn avoids inheriting open sockets
    q   = ctx.Queue()
    p   = ctx.Process(target=_prophet_worker,
                      args=(ts.index.tolist(), ts.values.tolist(), steps, q))
    p.start()
    p.join(timeout=60)           # wait up to 60 s

    if p.is_alive():             # timed out
        p.terminate()
        p.join()
        return exp_smoothing_forecast(ts, steps=steps)

    if p.exitcode != 0:          # native crash (SIGABRT / -6 / etc.)
        return exp_smoothing_forecast(ts, steps=steps)

    result = q.get_nowait()
    if isinstance(result, Exception):
        return exp_smoothing_forecast(ts, steps=steps)

    return np.maximum(np.asarray(result), 0)



def croston_forecast(ts, steps=12, alpha=0.1):

    demand = ts.values
    n = len(demand)

    q = np.zeros(n)
    a = np.zeros(n)

    first = np.argmax(demand > 0)

    q[first] = demand[first]
    a[first] = 1

    for t in range(first + 1, n):

        if demand[t] > 0:
            q[t] = q[t-1] + alpha * (demand[t] - q[t-1])
            a[t] = a[t-1] + alpha * (1 - a[t-1])
        else:
            q[t] = q[t-1]
            a[t] = a[t-1] + alpha * (1 - a[t-1])

    forecast = q[-1] / a[-1]
    return np.repeat(max(forecast, 0), steps)


# =============================
# ✅ FIXED ROLLING BACKTEST
# =============================

def rolling_backtest(ts, model_choice, test_size=6):

    errors = []

    for i in range(test_size, 0, -1):

        train = ts.iloc[:-i]
        test  = ts.iloc[-i]

        try:

            if model_choice in ("ARIMA", "AUTO_ARIMA"):

                order, seasonal_order = get_arima_order(train, "backtest")

                model = SARIMAX(
                    train,
                    order=order,
                    seasonal_order=seasonal_order,
                    enforce_stationarity=False,
                    enforce_invertibility=False
                )

                fit = model.fit(disp=False)
                pred = fit.forecast(1)[0]

            elif model_choice in ("EXP_SMOOTHING", "EXPONENTIAL_SMOOTHING", "ETS"):
                pred = exp_smoothing_forecast(train, steps=1)[0]

            elif model_choice == "PROPHET":
                pred = prophet_forecast(train, steps=1)[0]

            elif model_choice == "CROSTON":
                pred = croston_forecast(train, steps=1)[0]

            elif model_choice in ("LINEAR", "LINEAR_REGRESSION"):
                pred = linear_forecast(train, steps=1)[0]

            else:
                continue

            error = abs(test - pred)
            errors.append(error)

        except Exception:
            continue

    if len(errors) == 0:
        return None

    return np.mean(errors)


# =============================
# APPLY FORECAST BY MODEL
# =============================

def run_model(ts, model_choice, steps):
    """Dispatch to the right model and return (forecast_array, model_label)."""
    m = model_choice.upper().replace(" ", "_").replace("-", "_")

    if m in ("ARIMA", "AUTO_ARIMA"):
        order, seasonal_order = get_arima_order(ts, "main")
        sarimax = SARIMAX(
            ts,
            order=order,
            seasonal_order=seasonal_order,
            enforce_stationarity=False,
            enforce_invertibility=False
        )
        fit = sarimax.fit(disp=False)
        fc = np.maximum(fit.forecast(steps), 0)
        return fc, "ARIMA"

    elif m in ("EXP_SMOOTHING", "EXPONENTIAL_SMOOTHING", "ETS"):
        fc = exp_smoothing_forecast(ts, steps=steps)
        return fc, "Exp Smoothing"

    elif m == "PROPHET":
        fc = prophet_forecast(ts, steps=steps)
        return fc, "Prophet"

    elif m == "CROSTON":
        fc = croston_forecast(ts, steps=steps)
        return fc, "Croston"

    else:  # LINEAR, LINEAR_REGRESSION, default
        fc = linear_forecast(ts, steps=steps)
        return fc, "Linear Regression"


# =============================
# MAIN ENTRY POINT (stdin → stdout)
# =============================

import sys
import json

def main():
    try:
        input_data = sys.stdin.read()
        if not input_data.strip():
            print("[]")
            return

        data = json.loads(input_data)

        items               = data.get("items", [])
        forecast_periods_years = data.get("forecastPeriods", 1)
        model_choice        = data.get("model", "ARIMA")
        steps               = forecast_periods_years * 12

        results = []

        for item in items:
            item_id   = item.get("itemId")
            item_name = item.get("itemName")
            cat_id    = item.get("categoryId")
            cat_name  = item.get("categoryName")
            history   = item.get("history", [])

            if not history:
                continue

            # Build monthly time series
            df = pd.DataFrame(history)
            df["date"]     = pd.to_datetime(df["date"], errors="coerce")
            df["quantity"] = pd.to_numeric(df["quantity"], errors="coerce")
            df = df.dropna().sort_values("date")

            if df.empty:
                continue

            df.set_index("date", inplace=True)
            # Resample to MS buckets (safe for any day-of-month)
            ts = df["quantity"].resample("MS").sum().fillna(0)

            if len(ts) < 2:
                # For sparse items: use simple mean as flat forecast
                mean_val = ts.mean() if len(ts) > 0 else 0.0
                flat_fc  = max(mean_val, 0.0) * steps
                
                # Build monthly breakdown
                # If df is empty, df.index.max() might fail, so we fallback
                last_date = df.index.max() if not df.empty else pd.Timestamp.today()
                future_dates = pd.date_range(start=last_date + pd.DateOffset(months=1), periods=steps, freq="MS")
                monthly_breakdown = [
                    {"month": d.strftime("%b-%Y"), "quantity": round(max(mean_val, 0.0), 2)}
                    for d in future_dates
                ]

                # Accuracy: low (50%) for very sparse data
                results.append({
                    "itemId":             item_id,
                    "itemName":           item_name,
                    "categoryId":         cat_id,
                    "categoryName":       cat_name,
                    "forecastYear":       f"Next {forecast_periods_years} Year(s)",
                    "forecastedQuantity": round(flat_fc, 2),
                    "accuracyPercent":    50.0,
                    "monthlyBreakdown":   monthly_breakdown
                })
                continue

            # Run the selected model
            try:
                fc_array, model_label = run_model(ts, model_choice, steps)
            except Exception as e:
                # Fallback to linear if chosen model fails
                try:
                    fc_array, model_label = linear_forecast(ts, steps=steps), "Linear Regression"
                except Exception:
                    continue

            # ── Accuracy calculation ──────────────────────────────────
            # Linear Regression: use fast analytical R² (no backtest needed)
            m_upper = model_choice.upper().replace(" ", "_").replace("-", "_")
            if m_upper in ("LINEAR", "LINEAR_REGRESSION"):
                ss_res = np.sum((ts.values - LinearRegression().fit(
                    np.arange(len(ts)).reshape(-1, 1), ts.values
                ).predict(np.arange(len(ts)).reshape(-1, 1))) ** 2)
                ss_tot = np.sum((ts.values - ts.mean()) ** 2)
                r2 = 1 - ss_res / ss_tot if ss_tot > 0 else 0.0
                accuracy_pct = round(max(0.0, min(99.9, r2 * 100)), 2)
            elif len(ts) < 4:
                cv = ts.std() / ts.mean() if ts.mean() > 0 else 1.0
                accuracy_pct = max(0.0, min(100.0, 100.0 - cv * 50.0))
            else:
                accuracy_pct = 80.0
                # Use max 2 backtest steps to stay fast
                mae = rolling_backtest(ts, m_upper, test_size=min(2, len(ts) // 4))
                if mae is not None:
                    mean_val = ts.mean()
                    if mean_val > 0:
                        accuracy_pct = max(0.0, min(99.9, 100.0 - (mae / mean_val) * 100))
                    else:
                        accuracy_pct = 100.0

            # ── Monthly Breakdown ──────────────────────────────────
            last_date = ts.index.max() if len(ts) > 0 else pd.Timestamp.today()
            future_dates = pd.date_range(start=last_date + pd.DateOffset(months=1), periods=steps, freq="MS")
            
            monthly_breakdown = [
                {"month": d.strftime("%b-%Y"), "quantity": round(max(qty, 0.0), 2)}
                for d, qty in zip(future_dates, fc_array)
            ]

            total_forecast = float(np.sum(fc_array))
            period_label   = f"Next {forecast_periods_years} Year(s)"

            results.append({
                "itemId":             item_id,
                "itemName":           f"{item_name} ({model_label})",
                "categoryId":         cat_id,
                "categoryName":       cat_name,
                "forecastYear":       period_label,
                "forecastedQuantity": round(total_forecast, 2),
                "accuracyPercent":    round(accuracy_pct, 2),
                "monthlyBreakdown":   monthly_breakdown
            })

        print(json.dumps(results))

    except Exception as e:
        import traceback
        print(json.dumps([{"error": str(e), "traceback": traceback.format_exc()}]))
        sys.exit(1)


if __name__ == "__main__":
    main()
