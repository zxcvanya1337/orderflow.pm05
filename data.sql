-- [ Таблица users ]
INSERT INTO users (username, password_hash, email, role, full_name) VALUES
    ('admin_ivan', '$2b$12$LJ3m4...hash...', 'ivan@orderflow.ru', 'admin', 'Иванов Иван Иванович'),
    ('manager_anna', '$2b$12$LJ3m4...hash...', 'anna@orderflow.ru', 'manager', 'Петрова Анна Сергеевна'),
    ('warehouse_sergey', '$2b$12$LJ3m4...hash...', 'sergey@orderflow.ru', 'warehouse', 'Сидоров Сергей Петрович');

-- [ Таблица categories ]
INSERT INTO categories (name, description) VALUES
    ('Электроника', 'Смартфоны, ноутбуки и аксессуары'),
    ('Одежда', 'Мужская и женская одежда'),
    ('Бытовая техника', 'Крупная и мелкая бытовая техника');

-- [ Таблица products ]
INSERT INTO products (category_id, name, sku, price, stock_quantity, description, is_active) VALUES
    (1, 'Смартфон SuperPhone X', 'SPX-001', 59990.00, 15, 'Флагманский смартфон с отличной камерой', TRUE),
    (1, 'Ноутбук ProBook 15', 'PB15-002', 85000.00, 8, 'Мощный ноутбук для работы', TRUE),
    (2, 'Футболка базовая белая', 'TSH-WHT-001', 1200.00, 100, 'Хлопковая футболка унисекс', TRUE);

-- [ Таблица orders ]
INSERT INTO orders (user_id, customer_name, customer_phone, customer_email, status, total_amount, created_at, updated_at) VALUES
    (2, 'Смирнов Алексей', '+79001112233', 'alex@mail.ru', 'completed', 61190.00, '2026-05-10 10:30:00', '2026-05-12 14:00:00'),
    (2, 'Кузнецова Мария', '+79004445566', 'maria@gmail.com', 'processing', 85000.00, '2026-05-13 09:15:00', '2026-05-13 11:20:00'),
    (2, 'Волков Дмитрий', '+79007778899', 'volkov@ya.ru', 'new', 2400.00, '2026-05-14 08:45:00', NULL);

-- [ Таблица order_items ]
INSERT INTO order_items (order_id, product_id, quantity, price_at_moment) VALUES
    (1, 1, 1, 59990.00), -- Смартфон в первом заказе
    (1, 3, 1, 1200.00),  -- Футболка в первом заказе
    (2, 2, 1, 85000.00), -- Ноутбук во втором заказе
    (3, 3, 2, 1200.00);  -- Две футболки в третьем заказе

-- [ Таблица order_status_history ]
INSERT INTO order_status_history (order_id, old_status, new_status, changed_by, changed_at, comment) VALUES
    (1, NULL, 'new', 2, '2026-05-10 10:30:00', 'Заказ создан'),
    (1, 'new', 'processing', 2, '2026-05-10 11:00:00', 'Подтвержден менеджером'),
    (1, 'processing', 'shipped', 3, '2026-05-11 09:00:00', 'Передан в доставку'),
    (1, 'shipped', 'completed', 3, '2026-05-12 14:00:00', 'Доставлен клиенту'),
    (2, NULL, 'new', 2, '2026-05-13 09:15:00', 'Заказ создан'),
    (2, 'new', 'processing', 2, '2026-05-13 11:20:00', 'Ожидает сборки на складе'),
    (3, NULL, 'new', 2, '2026-05-14 08:45:00', 'Новый заказ от постоянного клиента');