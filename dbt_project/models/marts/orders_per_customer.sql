SELECT
    name as nome_completo,
    total_value as total_vendas
FROM
    {{ref("int_orders_per_customer")}}