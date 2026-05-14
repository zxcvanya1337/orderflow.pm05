-- ============================================================
-- База данных: orderflow_db
-- СУБД: PostgreSQL 15
-- ============================================================

-- Создание таблицы пользователей (users)
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    role VARCHAR(20) NOT NULL CHECK (role IN ('admin', 'manager', 'warehouse')),
    full_name VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Создание таблицы категорий (categories)
CREATE TABLE categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT
);

-- Создание таблицы товаров (products)
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
    name VARCHAR(150) NOT NULL,
    sku VARCHAR(50) UNIQUE NOT NULL,
    price DECIMAL(10, 2) NOT NULL CHECK (price >= 0),
    stock_quantity INTEGER NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE
);

-- Создание таблицы заказов (orders)
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    customer_name VARCHAR(100) NOT NULL,
    customer_phone VARCHAR(20) NOT NULL,
    customer_email VARCHAR(100),
    status VARCHAR(20) NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'processing', 'shipped', 'completed', 'cancelled')),
    total_amount DECIMAL(12, 2) DEFAULT 0 CHECK (total_amount >= 0),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP
);

-- Создание таблицы позиций заказа (order_items)
CREATE TABLE order_items (
    id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    price_at_moment DECIMAL(10, 2) NOT NULL CHECK (price_at_moment >= 0)
);

-- Создание таблицы истории статусов (order_status_history)
CREATE TABLE order_status_history (
    id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    old_status VARCHAR(20),
    new_status VARCHAR(20) NOT NULL,
    changed_by INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    changed_at TIMESTAMP DEFAULT NOW(),
    comment TEXT
);

-- Индексы для ускорения поиска и связей
CREATE INDEX idx_orders_user_id ON orders(user_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_products_category_id ON products(category_id);
CREATE INDEX idx_order_items_order_id ON order_items(order_id);
CREATE INDEX idx_order_items_product_id ON order_items(product_id);
CREATE INDEX idx_history_order_id ON order_status_history(order_id);