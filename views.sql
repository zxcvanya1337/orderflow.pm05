-- ============================================================
-- Views (Представления)
-- ============================================================

-- 1. Детализированная информация о заказах
CREATE OR REPLACE VIEW public.v_order_details AS
SELECT 
    o.id AS order_id,
    o.customer_name,
    o.customer_phone,
    o.status,
    o.total_amount,
    o.created_at,
    u.full_name AS manager_name,
    h.changed_at AS last_status_update
FROM public.orders o
JOIN public.users u ON o.user_id = u.id
LEFT JOIN public.order_status_history h ON (
    (o.id = h.order_id) 
    AND 
    (h.changed_at = (
        SELECT max(order_status_history.changed_at) AS max
        FROM public.order_status_history
        WHERE (order_status_history.order_id = o.id)
    ))
);

-- 2. Статистика продаж по категориям
CREATE OR REPLACE VIEW public.v_category_sales_stats AS
SELECT 
    c.name AS category_name,
    count(oi.id) AS total_items_sold,
    sum(((oi.quantity)::numeric * oi.price_at_moment)) AS total_revenue
FROM public.categories c
JOIN public.products p ON ((c.id = p.category_id))
LEFT JOIN public.order_items oi ON ((p.id = oi.product_id))
GROUP BY c.name;