-- ============================================================
-- Functions & Procedures (Функции и Процедуры)
-- ============================================================

-- 1. Функция для триггера: Логирование изменения статуса
CREATE OR REPLACE FUNCTION public.fn_log_order_status_change() RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO order_status_history (order_id, old_status, new_status, changed_by, changed_at)
        VALUES (NEW.id, OLD.status, NEW.status, 1, NOW()); -- Примечание: changed_by жестко задан как 1, в продакшене лучше использовать current_setting или передавать через контекст
    END IF;
    RETURN NEW;
END;
$$;

-- 2. Функция для триггера: Обновление timestamp
CREATE OR REPLACE FUNCTION public.fn_set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

-- 3. Процедура: Создание заказа
CREATE OR REPLACE PROCEDURE public.sp_create_order(
    IN p_user_id integer, 
    IN p_customer_name character varying, 
    IN p_customer_phone character varying, 
    IN p_items jsonb
)
    LANGUAGE plpgsql
AS $$
DECLARE
    v_order_id INTEGER;
    v_item JSONB;
    v_product_price DECIMAL(10, 2);
    v_current_stock INTEGER;
    v_total_amount DECIMAL(12, 2) := 0;
BEGIN
    -- 1. Создаем заказ со статусом 'new'
    INSERT INTO orders (user_id, customer_name, customer_phone, status, total_amount, created_at)
    VALUES (p_user_id, p_customer_name, p_customer_phone, 'new', 0, NOW())
    RETURNING id INTO v_order_id;

    -- 2. Обрабатываем каждую позицию из JSON
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        -- Получаем текущую цену и остаток
        SELECT price, stock_quantity INTO v_product_price, v_current_stock
        FROM products
        WHERE id = (v_item->>'product_id')::INTEGER;

        -- Проверка наличия
        IF v_current_stock < (v_item->>'quantity')::INTEGER THEN
            RAISE EXCEPTION 'Недостаточно товара на складе для продукта ID %', (v_item->>'product_id');
        END IF;

        -- Добавляем позицию в заказ
        INSERT INTO order_items (order_id, product_id, quantity, price_at_moment)
        VALUES (v_order_id, (v_item->>'product_id')::INTEGER, (v_item->>'quantity')::INTEGER, v_product_price);

        -- Обновляем общую сумму
        v_total_amount := v_total_amount + (v_product_price * (v_item->>'quantity')::INTEGER);

        -- Списываем товар со склада
        UPDATE products
        SET stock_quantity = stock_quantity - (v_item->>'quantity')::INTEGER
        WHERE id = (v_item->>'product_id')::INTEGER;
    END LOOP;

    -- 3. Обновляем итоговую сумму заказа
    UPDATE orders
    SET total_amount = v_total_amount
    WHERE id = v_order_id;

    -- 4. Логируем создание статуса
    INSERT INTO order_status_history (order_id, old_status, new_status, changed_by, changed_at)
    VALUES (v_order_id, NULL, 'new', p_user_id, NOW());

END;
$$;

-- 4. Процедура: Изменение статуса заказа
CREATE OR REPLACE PROCEDURE public.sp_change_order_status(
    IN p_order_id integer, 
    IN p_new_status character varying, 
    IN p_user_id integer
)
    LANGUAGE plpgsql
AS $$
DECLARE
    v_current_status VARCHAR(20);
BEGIN
    -- 1. Получаем текущий статус заказа
    SELECT status INTO v_current_status
    FROM orders
    WHERE id = p_order_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Заказ с ID % не найден', p_order_id;
    END IF;

    -- 2. Простая валидация логики переходов
    IF v_current_status = 'cancelled' OR v_current_status = 'completed' THEN
        RAISE EXCEPTION 'Нельзя изменить статус завершенного или отмененного заказа';
    END IF;

    IF p_new_status NOT IN ('new', 'processing', 'shipped', 'completed', 'cancelled') THEN
        RAISE EXCEPTION 'Некорректный статус: %', p_new_status;
    END IF;

    -- 3. Обновляем статус в основной таблице
    UPDATE orders
    SET status = p_new_status,
        updated_at = NOW()
    WHERE id = p_order_id;

    -- 4. Делаем запись в историю изменений
    INSERT INTO order_status_history (order_id, old_status, new_status, changed_by, changed_at)
    VALUES (p_order_id, v_current_status, p_new_status, p_user_id, NOW());

END;
$$;

-- 5. Процедура: Пополнение склада
CREATE OR REPLACE PROCEDURE public.sp_add_product_to_stock(
    IN p_product_id integer, 
    IN p_quantity integer
)
    LANGUAGE plpgsql
AS $$
BEGIN
    -- Проверка на существование товара
    IF NOT EXISTS (SELECT 1 FROM products WHERE id = p_product_id) THEN
        RAISE EXCEPTION 'Товар с ID % не найден', p_product_id;
    END IF;

    -- Проверка на положительное количество
    IF p_quantity <= 0 THEN
        RAISE EXCEPTION 'Количество должно быть больше нуля';
    END IF;

    -- Обновление остатков на складе
    UPDATE products
    SET stock_quantity = stock_quantity + p_quantity
    WHERE id = p_product_id;

END;
$$;

-- 6. Процедура: Регистрация пользователя
CREATE OR REPLACE PROCEDURE public.sp_register_user(
    IN p_username character varying, 
    IN p_email character varying, 
    IN p_hash character varying, 
    IN p_salt character varying, 
    IN p_role character varying, 
    IN p_full_name character varying
)
    LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO users (username, email, password_hash, password_salt, role, full_name, created_at)
    VALUES (p_username, p_email, p_hash, p_salt, p_role, p_full_name, NOW());
END;
$$;