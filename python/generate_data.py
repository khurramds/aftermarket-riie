"""
generate_data.py
Aftermarket RIIE - Synthetic Data Generator (Day 1, Block 3)

Generates the 6 SYNTHETIC tables into ../data/ as CSV:
    sku_master           (500)
    customer_master      (200)
    supplier_master      (45)
    sales_history        (~750,000)   Poisson demand for X-class, neg-binomial for Z-class
    returns              (~37,500)     ~5% return rate, weighted reason codes
    inventory_snapshot   (~26,000)     500 SKUs x 52 weekly snapshots, reorder params at 97% fill

The 7th table, location_master (48), is NOT generated here.
It uses real FHWA 2023 vehicle-registration data and is built separately.

DESIGN NOTE (read this for interviews):
  Each SKU is assigned a HIDDEN demand archetype (X / Y / Z) that drives how its
  weekly demand is simulated. That archetype is NOT written to sku_master. The
  abc_class / xyz_class / composite_score / tier_recommendation columns are left
  blank on purpose -- the Day 3 Python engine REDISCOVERS them from the generated
  sales. Pre-stamping them would be circular ("analyzing data you constructed").
  Same logic for customer rfm_segment / churn_probability.

Run from the repo root:   python python/generate_data.py
Or from inside python/:    python generate_data.py
"""

from pathlib import Path
import numpy as np
import pandas as pd
from faker import Faker

# ----------------------------------------------------------------------
# 0. Setup: deterministic seed + paths that work from anywhere in the repo
# ----------------------------------------------------------------------
SEED = 42
rng = np.random.default_rng(SEED)
fake = Faker("en_US")
Faker.seed(SEED)

BASE = Path(__file__).resolve().parent.parent      # ...\aftermarket-riie
DATA = BASE / "data"
DATA.mkdir(parents=True, exist_ok=True)

# Calibration knobs
N_SKU            = 500
N_CUSTOMER       = 200
N_SUPPLIER       = 45
YEARS            = 3
WEEKS            = YEARS * 52                       # 156 weekly periods
END_DATE         = pd.Timestamp("2026-05-30")      # most recent week-ending (a Saturday)
RETURN_RATE      = 0.05                             # ~5% of transactions
SERVICE_Z        = 1.88                             # z-score for 97% fill rate
CARRYING_RATE    = 0.25                             # 25% annual carrying cost (APICS convention)

# ----------------------------------------------------------------------
# Reference dimensions
# ----------------------------------------------------------------------
CATEGORIES = [
    "Brake Components", "Filters", "Belts & Hoses", "Ignition & Spark",
    "Batteries & Electrical", "Suspension & Steering", "Engine Cooling",
    "Fuel System", "Exhaust & Emissions", "Timing Components",
    "Lighting & Wipers", "Fluids & Chemicals",
]
# realistic per-category (low_cost, high_cost, margin_low, margin_high)
CAT_ECON = {
    "Brake Components":       (8,   140, 0.30, 0.48),
    "Filters":                (2,    35, 0.40, 0.62),
    "Belts & Hoses":          (4,    90, 0.32, 0.50),
    "Ignition & Spark":       (3,   120, 0.35, 0.55),
    "Batteries & Electrical": (40,  260, 0.20, 0.38),
    "Suspension & Steering":  (15,  320, 0.28, 0.46),
    "Engine Cooling":         (10,  220, 0.30, 0.48),
    "Fuel System":            (12,  280, 0.30, 0.50),
    "Exhaust & Emissions":    (20,  400, 0.26, 0.44),
    "Timing Components":      (18,  340, 0.34, 0.54),
    "Lighting & Wipers":      (3,    80, 0.42, 0.64),
    "Fluids & Chemicals":     (4,    45, 0.38, 0.58),
}

# 6 sales regions -> states (lower 48)
REGION_STATES = {
    "Northeast": ["ME","NH","VT","MA","RI","CT","NY","NJ","PA"],
    "Southeast": ["DE","MD","VA","WV","NC","SC","GA","FL","KY","TN","AL","MS"],
    "Midwest":   ["OH","MI","IN","IL","WI","MN","IA","MO"],
    "Plains":    ["ND","SD","NE","KS","OK"],
    "Southwest": ["TX","NM","AZ","CO","UT","NV"],
    "West":      ["CA","OR","WA","ID","MT","WY","AR","LA"],
}
STATE_TO_REGION = {s: r for r, ss in REGION_STATES.items() for s in ss}
ALL_STATES = list(STATE_TO_REGION.keys())

CUSTOMER_TYPES = ["National Retail Chain", "Regional Warehouse Distributor",
                  "Independent Jobber", "Fleet / Commercial", "E-commerce / Online"]
CREDIT_TERMS   = ["Net 30", "Net 45", "Net 60", "2/10 Net 30"]
ORDER_CHANNELS = ["EDI", "Web Portal", "Phone / CSR", "Field Rep", "API"]
RETURN_REASONS = ["Wrong Part", "Defective", "Overstock", "Duplicate Order", "Damaged in Transit"]
RETURN_WEIGHTS = [0.38, 0.22, 0.19, 0.12, 0.09]

print("Generating synthetic data ...")

# ======================================================================
# 1. SUPPLIER MASTER (45)
# ======================================================================
import_countries   = ["China", "Mexico", "Taiwan", "India", "Germany", "South Korea"]
domestic_share     = 0.40
supplier_rows = []
for i in range(1, N_SUPPLIER + 1):
    is_domestic = rng.random() < domestic_share
    country = "USA" if is_domestic else rng.choice(import_countries)
    lead = int(rng.integers(3, 8)) if is_domestic else int(rng.integers(21, 46))
    tariff = 0.0 if is_domestic else round(float(rng.uniform(2.5, 25.0)), 1)
    supplier_rows.append({
        "supplier_id":          f"SUP{i:03d}",
        "supplier_name":        fake.company().replace(",", ""),
        "country_of_origin":    country,
        "lead_time_days":       lead,
        "quality_score":        round(float(rng.uniform(80, 99)), 1),
        "tariff_exposure":      tariff,
        "min_order_qty":        int(rng.choice([25, 50, 100, 150, 250, 500])),
        "on_time_delivery_pct": round(float(rng.uniform(82, 99)), 1),
    })
suppliers = pd.DataFrame(supplier_rows)

# ======================================================================
# 2. SKU MASTER (500)  -- analytical columns left blank on purpose
# ======================================================================
# hidden demand archetype drives sales simulation; NOT written to CSV
archetypes = rng.choice(["X", "Y", "Z"], size=N_SKU, p=[0.40, 0.35, 0.25])
# hidden volume tier -> base weekly order frequency (lambda)
vol_tier   = rng.choice(["A", "B", "C"], size=N_SKU, p=[0.20, 0.30, 0.50])
lam = np.where(vol_tier == "A", rng.uniform(22, 35, N_SKU),
        np.where(vol_tier == "B", rng.uniform(7, 13, N_SKU),
                 rng.uniform(1, 4, N_SKU)))
lam *= 0.93                                          # calibrate grand total toward ~750K lines

sku_rows = []
for i in range(N_SKU):
    cat = CATEGORIES[i % len(CATEGORIES)] if i < len(CATEGORIES) else rng.choice(CATEGORIES)
    lo, hi, m_lo, m_hi = CAT_ECON[cat]
    unit_cost = round(float(rng.uniform(lo, hi)), 2)
    margin    = round(float(rng.uniform(m_lo, m_hi)), 4)
    list_price = round(unit_cost / (1 - margin), 2)
    sku_rows.append({
        "sku_id":             f"SKU{i+1:05d}",
        "category":           cat,
        "unit_cost":          unit_cost,
        "list_price":         list_price,
        "gross_margin_pct":   round(margin * 100, 2),
        "fitment_breadth":    int(rng.integers(1, 480)),     # # vehicle applications
        "supplier_count":     int(rng.integers(1, 5)),
        "is_private_label":   int(rng.random() < 0.30),
        "abc_class":          "",   # <- Day 3 engine
        "xyz_class":          "",   # <- Day 3 engine
        "composite_score":    "",   # <- Day 3 engine
        "tier_recommendation": "",  # <- Day 3 engine
    })
skus = pd.DataFrame(sku_rows)

# ======================================================================
# 3. CUSTOMER MASTER (200)  -- rfm/churn left blank on purpose
# ======================================================================
managers = [fake.name() for _ in range(12)]
cust_rows = []
for i in range(1, N_CUSTOMER + 1):
    state = rng.choice(ALL_STATES)
    cust_rows.append({
        "customer_id":       f"CUST{i:04d}",
        "customer_name":     fake.company().replace(",", ""),
        "customer_type":     rng.choice(CUSTOMER_TYPES, p=[0.10, 0.22, 0.40, 0.18, 0.10]),
        "primary_state":     state,
        "region":            STATE_TO_REGION[state],
        "account_manager":   rng.choice(managers),
        "credit_terms":      rng.choice(CREDIT_TERMS, p=[0.45, 0.25, 0.18, 0.12]),
        "customer_since":    fake.date_between(start_date="-12y", end_date="-1y").isoformat(),
        "credit_limit":      int(rng.choice([10000, 25000, 50000, 100000, 250000, 500000])),
        "rfm_segment":       "",   # <- Day 3 engine
        "churn_probability": "",   # <- Day 3 engine
    })
customers = pd.DataFrame(cust_rows)

# customer purchase weight (some buy a lot more than others)
cust_weight = rng.dirichlet(np.ones(N_CUSTOMER) * 0.7)

# ======================================================================
# 4. SALES HISTORY (~750,000)
# ======================================================================
week_ends = pd.date_range(end=END_DATE, periods=WEEKS, freq="W-SAT")
WEEKS = len(week_ends)                              # reconcile (W-SAT anchoring can shift by one)
woy = week_ends.isocalendar().week.to_numpy()
# mild seasonal lift: spring/fall service peaks
seasonal = 1.0 + 0.18 * np.sin((woy - 10) / 52 * 2 * np.pi) \
               + 0.10 * np.sin((woy - 36) / 52 * 2 * np.pi)

list_prices = skus["list_price"].to_numpy()
cust_ids    = customers["customer_id"].to_numpy()
cust_states = customers["primary_state"].to_numpy()

frames = []
txn_counter = 0
for s in range(N_SKU):
    arche = archetypes[s]
    base  = lam[s] * seasonal                       # length WEEKS expected weekly orders
    if arche == "X":                                # stable -> Poisson
        counts = rng.poisson(base)
    elif arche == "Y":                              # moderate -> mild over-dispersion
        r = 8.0
        p = r / (r + base)
        counts = rng.negative_binomial(r, p)
    else:                                           # Z -> erratic, spiky
        r = 0.8
        p = r / (r + base)
        counts = rng.negative_binomial(r, p)

    n = int(counts.sum())
    if n == 0:
        continue

    week_idx   = np.repeat(np.arange(WEEKS), counts)
    # spread each week's orders across the 7 days
    order_dts  = week_ends.values[week_idx] - (rng.integers(0, 7, n) * np.timedelta64(1, "D"))
    ship_lag   = rng.integers(1, 4, n) * np.timedelta64(1, "D")
    cust_pick  = rng.choice(np.arange(N_CUSTOMER), size=n, p=cust_weight)

    units_ord  = 1 + rng.poisson(2.0, n)            # small case-pack style quantities
    short      = rng.random(n) < 0.03               # ~3% lines short-shipped (stockout)
    units_shp  = np.where(short, np.maximum(0, units_ord - rng.integers(1, 3, n)), units_ord)

    disc       = np.round(rng.choice([0.0, 0.05, 0.10, 0.15, 0.20, 0.25], size=n,
                                     p=[0.30, 0.25, 0.20, 0.13, 0.08, 0.04]), 2)
    unit_price = np.round(list_prices[s] * (1 - disc), 2)
    revenue    = np.round(units_shp * unit_price, 2)

    ids = np.arange(txn_counter, txn_counter + n)
    txn_counter += n

    frames.append(pd.DataFrame({
        "transaction_id": [f"TXN{j:08d}" for j in ids],
        "order_date":     pd.to_datetime(order_dts).date,
        "ship_date":      pd.to_datetime(order_dts + ship_lag).date,
        "sku_id":         skus["sku_id"].iloc[s],
        "customer_id":    cust_ids[cust_pick],
        "state_code":     cust_states[cust_pick],
        "units_ordered":  units_ord,
        "units_shipped":  units_shp,
        "unit_price":     unit_price,
        "discount_pct":   np.round(disc * 100, 2),
        "revenue":        revenue,
        "order_channel":  rng.choice(ORDER_CHANNELS, size=n, p=[0.34, 0.26, 0.18, 0.14, 0.08]),
    }))

sales = pd.concat(frames, ignore_index=True)

# ======================================================================
# 5. RETURNS (~5% of transactions)
# ======================================================================
ship_mask  = sales["units_shipped"].to_numpy() > 0
elig_idx   = np.flatnonzero(ship_mask)
n_ret      = int(len(sales) * RETURN_RATE)
ret_idx    = rng.choice(elig_idx, size=n_ret, replace=False)
rsrc       = sales.iloc[ret_idx].reset_index(drop=True)

reasons    = rng.choice(RETURN_REASONS, size=n_ret, p=RETURN_WEIGHTS)
restockable = np.isin(reasons, ["Overstock", "Duplicate Order"]) | \
              ((reasons == "Wrong Part") & (rng.random(n_ret) < 0.5))
units_ret  = np.maximum(1, np.minimum(rsrc["units_shipped"].to_numpy(),
                                      rng.integers(1, 4, n_ret)))
ret_date   = pd.to_datetime(rsrc["ship_date"]) + pd.to_timedelta(rng.integers(3, 31, n_ret), unit="D")
ret_value  = np.round(units_ret * rsrc["unit_price"].to_numpy(), 2)

returns = pd.DataFrame({
    "return_id":      [f"RET{i:07d}" for i in range(n_ret)],
    "transaction_id": rsrc["transaction_id"],
    "sku_id":         rsrc["sku_id"],
    "customer_id":    rsrc["customer_id"],
    "return_date":    ret_date.dt.date,
    "units_returned": units_ret,
    "return_reason":  reasons,
    "return_value":   ret_value,
    "restockable":    restockable.astype(int),
    "handling_cost":  np.round(units_ret * rng.uniform(1.5, 6.0, n_ret), 2),
})

# ======================================================================
# 6. INVENTORY SNAPSHOT (500 SKUs x 52 weeks = 26,000)
# ======================================================================
# avg daily demand per SKU from the most recent 52 weeks of shipped units
last_year_start = END_DATE - pd.Timedelta(weeks=52)
recent = sales[pd.to_datetime(sales["order_date"]) >= last_year_start]
dmd = recent.groupby("sku_id")["units_shipped"].sum().reindex(skus["sku_id"]).fillna(0)
avg_daily = (dmd / 364.0).to_numpy()                       # units/day
avg_daily = np.where(avg_daily <= 0, 0.05, avg_daily)      # floor so days_on_hand is finite

cost_arr  = skus["unit_cost"].to_numpy()
# lead time per SKU: borrow from a random supplier draw, pivot to demand
lead_days = rng.integers(3, 46, N_SKU)
demand_std_daily = avg_daily * 0.6                          # rough demand variability
reorder_point = np.ceil(avg_daily * lead_days + SERVICE_Z * demand_std_daily * np.sqrt(lead_days))
reorder_qty   = np.ceil(avg_daily * 28)                     # ~4 weeks of cover

snap_weeks = pd.date_range(end=END_DATE, periods=52, freq="W-SAT")
snap_frames = []
snap_counter = 0
for s in range(N_SKU):
    rp  = reorder_point[s]
    rq  = max(reorder_qty[s], 1)
    # on-hand oscillates between just-reordered and near/at stockout
    on_hand = np.maximum(0, np.round(rng.uniform(0, rp + rq, 52))).astype(int)
    # inject occasional true stockouts for low movers
    if avg_daily[s] < 0.5:
        on_hand[rng.random(52) < 0.15] = 0
    on_order = np.where(on_hand <= rp, int(rq), 0)
    days_on_hand = np.round(on_hand / avg_daily[s], 1)
    ids = np.arange(snap_counter, snap_counter + 52)
    snap_counter += 52
    snap_frames.append(pd.DataFrame({
        "snapshot_id":     [f"SNP{j:07d}" for j in ids],
        "week_ending":     snap_weeks.date,
        "sku_id":          skus["sku_id"].iloc[s],
        "units_on_hand":   on_hand,
        "units_on_order":  on_order,
        "reorder_point":   int(rp),
        "reorder_qty":     int(rq),
        "days_on_hand":    days_on_hand,
        "inventory_value": np.round(on_hand * cost_arr[s], 2),
        "stockout_flag":   (on_hand == 0).astype(int),
    }))
inventory = pd.concat(snap_frames, ignore_index=True)

# ======================================================================
# 7. WRITE CSVs
# ======================================================================
outputs = {
    "sku_master":         skus,
    "customer_master":    customers,
    "supplier_master":    suppliers,
    "sales_history":      sales,
    "returns":            returns,
    "inventory_snapshot": inventory,
}
print("\nRow counts written to", DATA)
print("-" * 48)
for name, df in outputs.items():
    df.to_csv(DATA / f"{name}.csv", index=False)
    print(f"  {name:<20} {len(df):>9,} rows")
print("-" * 48)
print("Done. 6 CSV files in /data/. (location_master is built separately from FHWA data.)")
