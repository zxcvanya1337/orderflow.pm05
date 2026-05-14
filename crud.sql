INSERT INTO orders (user_id, customer_name, customer_phone, status, total_amount)
VALUES (2, 'Иванов Иван', '+79991234567', 'new', 0.00);

SELECT * FROM orders;

SELECT * FROM v_order_details WHERE order_id = 1;

SELECT id, customer_name, total_amount 
FROM orders 
WHERE status = 'new';

UPDATE orders 
SET status = 'processing', updated_at = NOW() 
WHERE id = 1;

UPDATE orders 
SET total_amount = 15000.00 
WHERE id = 1;

DELETE FROM orders 
WHERE id = 1;

DELETE FROM orders 
WHERE id = 2 AND status = 'cancelled';