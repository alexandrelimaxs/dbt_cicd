SELECT
  order_id,
  item_id,
  product_id,
  quantity,
  list_price,
  "USD" as currency,
  discount
FROM
  `estudos-414618.raw_data.order_items`