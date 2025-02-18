SELECT
    order_id,
    customer_id,
    order_status,
    order_date,
    required_date,
    shipped_date,
    store_id,
    staff_id,
    '1' as custom_id 
FROM
    `estudos-414618.raw_data.orders`