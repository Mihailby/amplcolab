reset;

### SETS
param T >= 0 ;                  # Number of weeks in the planning horizon
set PROD ;                      # Products, each modeled separately
set CHAIN_ATTR ;                # Attributes of the retail chain (e.g., storage cost, warehouse space)
set PAYMENT_SCHEME ;            # Different payment schemes ('A', 'B', 'C') with specific terms
set PAYMENT_ATTR ;              # Attributes of payment schemes (e.g., fraction paid upfront, payment delay)
set LINKS within {PROD, 1..T} ; # Links between products and weeks for demand

### PARAMETERS
param demand {LINKS} >= 0 ;                         # Weekly demand for each product
param area {PROD} default 1 ;                       # Area occupied by each product
param cost {PROD, PAYMENT_SCHEME} >= 0 ;            # Cost per product under each payment scheme 
param chain_attr {CHAIN_ATTR} >= 0 ;                # Retail chain attributes (e.g., storage cost, initial cash)
param scheme_attr {PAYMENT_SCHEME, PAYMENT_ATTR} >= 0 ; # Attributes of each payment scheme
param discount_rate >= 0 ;                          # Annual discount rate for time value of money
param BigM = 10e4;                                  # Large constant for constraint modeling

### VARIABLES
var UnitsPurchased {PROD, 1..T, PAYMENT_SCHEME } >= 0 ;     # Units UnitsPurchased for each scheme in each period
var SchemeSelected {PROD, 1..T, PAYMENT_SCHEME} binary;     # Binary indicator for chosen scheme per product and period

var UnitsSold {(p,t) in LINKS, s in PAYMENT_SCHEME} >= 0 ;  # Units sold per product, time, and payment scheme
var InventoryLevel {PROD, 1..T, PAYMENT_SCHEME} ;           # Inventory level per product, scheme, and time
var CashFlow {1..T} >= 0 ;                                  # Available cash flow per period


### OBJECTIVE
# Maximize total profit (revenues - costs - storage costs, discounted over time)
maximize TotalProfit: 
    sum{t in 1..T, s in PAYMENT_SCHEME} (
        sum{(p,t) in LINKS} UnitsSold[p,t,s] * cost[p,s] * chain_attr['markup'] # Revenue
        - sum{p in PROD} InventoryLevel[p,t,s] * chain_attr['storage_cost'])    # Storage cost
        * (1 / (1 + discount_rate)^t) ;                                         # Discount factor


### CONSTRAINTS
# 1. Inventory dynamics: Update inventory levels based on purchases and sales
s.t. InventoryDynamics {p in PROD, t in 1..T, s in PAYMENT_SCHEME}:
    InventoryLevel[p,t,s] = 
        (if t = 1 then 0 else InventoryLevel[p,t-1,s])      # Previous period's inventory
        + UnitsPurchased[p,t,s]                             # Current period purchases
        - sum {(pp,tt) in LINKS: pp=p && tt=t} UnitsSold[p,t,s];            # Units sold in current period

# 2. Cash flow dynamics: Update cash flow based on revenue, costs, and storage expenses
s.t. CashFlowConstraint {t in 1..T}:
    CashFlow[t] = 
        (if t = 1 then chain_attr['start_money'] else CashFlow[t-1])                                # Previous period's cash or initial cash
        + sum {(p,t) in LINKS, s in PAYMENT_SCHEME} (
            UnitsSold[p,t,s] * cost[p,s] * (1 + chain_attr['markup'])                               # Revenue
            - UnitsPurchased[p,t,s] * cost[p,s] * scheme_attr[s, 'payment_fraction_now']            # Immediate payment
            - sum {tt in 1..T: tt = t - scheme_attr[s, 'payment_delay'] and tt >= 1}
                UnitsPurchased[p,tt,s] * cost[p,s] * (1 - scheme_attr[s, 'payment_fraction_now']))  # Delayed payment
        - sum{p in PROD, s in PAYMENT_SCHEME} InventoryLevel[p,t,s] * chain_attr['storage_cost'] ;  # Storage cost

# 3. Scheme selection: Only one payment scheme can be selected for a product in each period
s.t. SingleSchemeSelection {p in PROD, t in 1..T}:
    sum {s in PAYMENT_SCHEME} SchemeSelected[p,t,s] = 1;

# 4. Warehouse capacity: Total inventory across all products and schemes must fit within warehouse space
s.t. WarehouseCapacity{t in 1..T}:
    sum{p in PROD, s in PAYMENT_SCHEME} InventoryLevel[p,t,s] 
    <= chain_attr['warehouse_space'];

# 5. Demand satisfaction: Total sales cannot exceed demand for each product in each period
s.t. DemandSatisfaction {(p,t) in LINKS}:
    sum{s in PAYMENT_SCHEME} UnitsSold[p,t,s] <= demand[p,t] ;

# 6. Purchase balance: Ensure purchases stay within available cash flow
s.t. PurchaseDynamics {t in 1..T}:
    sum{p in PROD, s in PAYMENT_SCHEME} UnitsPurchased[p,t,s] * cost[p,s]
    <= CashFlow[t] ;

# 7. Sales balance: Sales cannot exceed available inventory
s.t. SalesBalance{(p,t) in LINKS, s in PAYMENT_SCHEME}:
    UnitsSold[p,t,s] <= (if t = 1 then 0 else InventoryLevel[p,t-1,s]) ;

# 8. Link purchases to selected schemes: Enforce purchases to match selected schemes
s.t. PurchaseSchemeLink {p in PROD, t in 1..T, s in PAYMENT_SCHEME}:
    UnitsPurchased[p,t,s] - BigM * SchemeSelected[p,t,s] <= 0;