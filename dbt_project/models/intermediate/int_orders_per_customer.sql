with orders as (
    SELECT
        order_id,
        customer_id
    FROM
        {{ref("stg_orders")}}
),
customers as (
    SELECT
        customer_id,
        first_name,
        last_name
    FROM
        {{ref("stg_customers")}}
),
order_items as (
    SELECT
        list_price,
        quantity,
        order_id
    FROM
        {{ref("stg_order_items")}}
)

SELECT
    CONCAT(c.first_name, ' ', c.last_name) as name,
    ROUND(SUM(oi.list_price * oi.quantity), 2) AS total_value
FROM
    customers AS c
INNER JOIN
    orders AS o
ON
    c.customer_id = o.order_id
INNER JOIN
    order_items AS oi 
ON
    o.order_id = oi.order_id
GROUP BY
    ALL

