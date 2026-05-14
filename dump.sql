--
-- PostgreSQL database dump
--

\restrict OOioTUh74dHfjzfiATAekRIpTR03dT2vWtRIB6TT5wztdq4liw37UeKAN2uSf40

-- Dumped from database version 15.17 (Debian 15.17-1.pgdg13+1)
-- Dumped by pg_dump version 15.17 (Debian 15.17-1.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: fn_log_order_status_change(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_log_order_status_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO order_status_history (order_id, old_status, new_status, changed_by, changed_at)
        VALUES (NEW.id, OLD.status, NEW.status, 1, NOW());
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_log_order_status_change() OWNER TO postgres;

--
-- Name: fn_set_updated_at(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_set_updated_at() OWNER TO postgres;

--
-- Name: sp_add_product_to_stock(integer, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_add_product_to_stock(IN p_product_id integer, IN p_quantity integer)
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


ALTER PROCEDURE public.sp_add_product_to_stock(IN p_product_id integer, IN p_quantity integer) OWNER TO postgres;

--
-- Name: sp_change_order_status(integer, character varying, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_change_order_status(IN p_order_id integer, IN p_new_status character varying, IN p_user_id integer)
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

    -- 2. Простая валидация логики переходов (пример)
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


ALTER PROCEDURE public.sp_change_order_status(IN p_order_id integer, IN p_new_status character varying, IN p_user_id integer) OWNER TO postgres;

--
-- Name: sp_create_order(integer, character varying, character varying, jsonb); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_create_order(IN p_user_id integer, IN p_customer_name character varying, IN p_customer_phone character varying, IN p_items jsonb)
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


ALTER PROCEDURE public.sp_create_order(IN p_user_id integer, IN p_customer_name character varying, IN p_customer_phone character varying, IN p_items jsonb) OWNER TO postgres;

--
-- Name: sp_register_user(character varying, character varying, character varying, character varying, character varying, character varying); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_register_user(IN p_username character varying, IN p_email character varying, IN p_hash character varying, IN p_salt character varying, IN p_role character varying, IN p_full_name character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO users (username, email, password_hash, password_salt, role, full_name, created_at)
    VALUES (p_username, p_email, p_hash, p_salt, p_role, p_full_name, NOW());
END;
$$;


ALTER PROCEDURE public.sp_register_user(IN p_username character varying, IN p_email character varying, IN p_hash character varying, IN p_salt character varying, IN p_role character varying, IN p_full_name character varying) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.categories (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    description text
);


ALTER TABLE public.categories OWNER TO postgres;

--
-- Name: categories_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.categories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.categories_id_seq OWNER TO postgres;

--
-- Name: categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.categories_id_seq OWNED BY public.categories.id;


--
-- Name: order_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.order_items (
    id integer NOT NULL,
    order_id integer NOT NULL,
    product_id integer NOT NULL,
    quantity integer NOT NULL,
    price_at_moment numeric(10,2) NOT NULL,
    CONSTRAINT order_items_price_at_moment_check CHECK ((price_at_moment >= (0)::numeric)),
    CONSTRAINT order_items_quantity_check CHECK ((quantity > 0))
);


ALTER TABLE public.order_items OWNER TO postgres;

--
-- Name: order_items_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.order_items_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.order_items_id_seq OWNER TO postgres;

--
-- Name: order_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.order_items_id_seq OWNED BY public.order_items.id;


--
-- Name: order_status_history; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.order_status_history (
    id integer NOT NULL,
    order_id integer NOT NULL,
    old_status character varying(20),
    new_status character varying(20) NOT NULL,
    changed_by integer NOT NULL,
    changed_at timestamp without time zone DEFAULT now(),
    comment text
);


ALTER TABLE public.order_status_history OWNER TO postgres;

--
-- Name: order_status_history_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.order_status_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.order_status_history_id_seq OWNER TO postgres;

--
-- Name: order_status_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.order_status_history_id_seq OWNED BY public.order_status_history.id;


--
-- Name: orders; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.orders (
    id integer NOT NULL,
    user_id integer NOT NULL,
    customer_name character varying(100) NOT NULL,
    customer_phone character varying(20) NOT NULL,
    customer_email character varying(100),
    status character varying(20) DEFAULT 'new'::character varying NOT NULL,
    total_amount numeric(12,2) DEFAULT 0,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone,
    CONSTRAINT orders_status_check CHECK (((status)::text = ANY ((ARRAY['new'::character varying, 'processing'::character varying, 'shipped'::character varying, 'completed'::character varying, 'cancelled'::character varying])::text[]))),
    CONSTRAINT orders_total_amount_check CHECK ((total_amount >= (0)::numeric))
);


ALTER TABLE public.orders OWNER TO postgres;

--
-- Name: orders_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.orders_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.orders_id_seq OWNER TO postgres;

--
-- Name: orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.orders_id_seq OWNED BY public.orders.id;


--
-- Name: products; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.products (
    id integer NOT NULL,
    category_id integer NOT NULL,
    name character varying(150) NOT NULL,
    sku character varying(50) NOT NULL,
    price numeric(10,2) NOT NULL,
    stock_quantity integer DEFAULT 0 NOT NULL,
    description text,
    is_active boolean DEFAULT true,
    CONSTRAINT products_price_check CHECK ((price >= (0)::numeric)),
    CONSTRAINT products_stock_quantity_check CHECK ((stock_quantity >= 0))
);


ALTER TABLE public.products OWNER TO postgres;

--
-- Name: products_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.products_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.products_id_seq OWNER TO postgres;

--
-- Name: products_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.products_id_seq OWNED BY public.products.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id integer NOT NULL,
    username character varying(50) NOT NULL,
    password_hash character varying(255) NOT NULL,
    email character varying(100) NOT NULL,
    role character varying(20) NOT NULL,
    full_name character varying(100),
    created_at timestamp without time zone DEFAULT now(),
    password_salt character varying(255),
    CONSTRAINT users_role_check CHECK (((role)::text = ANY ((ARRAY['admin'::character varying, 'manager'::character varying, 'warehouse'::character varying])::text[])))
);


ALTER TABLE public.users OWNER TO postgres;

--
-- Name: COLUMN users.password_hash; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.users.password_hash IS 'Хэш пароля, сгенерированный с использованием соли';


--
-- Name: COLUMN users.password_salt; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.users.password_salt IS 'Случайная соль для хеширования пароля';


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.users_id_seq OWNER TO postgres;

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: v_category_sales_stats; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_category_sales_stats AS
 SELECT c.name AS category_name,
    count(oi.id) AS total_items_sold,
    sum(((oi.quantity)::numeric * oi.price_at_moment)) AS total_revenue
   FROM ((public.categories c
     JOIN public.products p ON ((c.id = p.category_id)))
     LEFT JOIN public.order_items oi ON ((p.id = oi.product_id)))
  GROUP BY c.name;


ALTER TABLE public.v_category_sales_stats OWNER TO postgres;

--
-- Name: v_order_details; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_order_details AS
 SELECT o.id AS order_id,
    o.customer_name,
    o.customer_phone,
    o.status,
    o.total_amount,
    o.created_at,
    u.full_name AS manager_name,
    h.changed_at AS last_status_update
   FROM ((public.orders o
     JOIN public.users u ON ((o.user_id = u.id)))
     LEFT JOIN public.order_status_history h ON (((o.id = h.order_id) AND (h.changed_at = ( SELECT max(order_status_history.changed_at) AS max
           FROM public.order_status_history
          WHERE (order_status_history.order_id = o.id))))));


ALTER TABLE public.v_order_details OWNER TO postgres;

--
-- Name: categories id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories ALTER COLUMN id SET DEFAULT nextval('public.categories_id_seq'::regclass);


--
-- Name: order_items id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items ALTER COLUMN id SET DEFAULT nextval('public.order_items_id_seq'::regclass);


--
-- Name: order_status_history id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_status_history ALTER COLUMN id SET DEFAULT nextval('public.order_status_history_id_seq'::regclass);


--
-- Name: orders id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders ALTER COLUMN id SET DEFAULT nextval('public.orders_id_seq'::regclass);


--
-- Name: products id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products ALTER COLUMN id SET DEFAULT nextval('public.products_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Data for Name: categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.categories (id, name, description) FROM stdin;
1	Электроника	Смартфоны, ноутбуки и аксессуары
2	Одежда	Мужская и женская одежда
3	Бытовая техника	Крупная и мелкая бытовая техника
\.


--
-- Data for Name: order_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.order_items (id, order_id, product_id, quantity, price_at_moment) FROM stdin;
1	1	1	1	59990.00
2	1	3	1	1200.00
3	2	2	1	85000.00
4	3	3	2	1200.00
5	4	1	1	59990.00
6	4	3	2	1200.00
\.


--
-- Data for Name: order_status_history; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.order_status_history (id, order_id, old_status, new_status, changed_by, changed_at, comment) FROM stdin;
1	1	\N	new	2	2026-05-10 10:30:00	Заказ создан
2	1	new	processing	2	2026-05-10 11:00:00	Подтвержден менеджером
3	1	processing	shipped	3	2026-05-11 09:00:00	Передан в доставку
4	1	shipped	completed	3	2026-05-12 14:00:00	Доставлен клиенту
5	2	\N	new	2	2026-05-13 09:15:00	Заказ создан
6	2	new	processing	2	2026-05-13 11:20:00	Ожидает сборки на складе
7	3	\N	new	2	2026-05-14 08:45:00	Новый заказ от постоянного клиента
8	4	\N	new	2	2026-05-14 11:13:14.097601	\N
9	2	processing	processing	2	2026-05-14 11:16:29.605961	\N
12	3	new	shipped	1	2026-05-14 11:30:01.50465	\N
\.


--
-- Data for Name: orders; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.orders (id, user_id, customer_name, customer_phone, customer_email, status, total_amount, created_at, updated_at) FROM stdin;
1	2	Смирнов Алексей	+79001112233	alex@mail.ru	completed	61190.00	2026-05-10 10:30:00	2026-05-12 14:00:00
4	2	Тестовый Клиент	+79990000000	\N	new	62390.00	2026-05-14 11:13:14.097601	\N
2	2	Кузнецова Мария	+79004445566	maria@gmail.com	processing	85000.00	2026-05-13 09:15:00	2026-05-14 11:16:29.605961
3	2	Волков Дмитрий	+79007778899	volkov@ya.ru	shipped	2400.00	2026-05-14 08:45:00	2026-05-14 11:30:01.50465
\.


--
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.products (id, category_id, name, sku, price, stock_quantity, description, is_active) FROM stdin;
2	1	Ноутбук ProBook 15	PB15-002	85000.00	8	Мощный ноутбук для работы	t
3	2	Футболка базовая белая	TSH-WHT-001	1200.00	98	Хлопковая футболка унисекс	t
1	1	Смартфон SuperPhone X	SPX-001	59990.00	64	Флагманский смартфон с отличной камерой	t
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (id, username, password_hash, email, role, full_name, created_at, password_salt) FROM stdin;
1	admin_ivan	$2b$12$LJ3m4...hash...	ivan@orderflow.ru	admin	Иванов Иван Иванович	2026-05-14 11:04:56.499824	\N
3	warehouse_sergey	$2b$12$LJ3m4...hash...	sergey@orderflow.ru	warehouse	Сидоров Сергей Петрович	2026-05-14 11:04:56.499824	\N
4	NGsGCHkY	e36c0b5faa774c60bb6c1b7803ce26360d1bddaf46f656b690078a1f96acd65c	example@example.com	manager	Example User	2026-05-14 12:30:26.676002	d2b26c2a679448b66f3ec116214811ea0eb0758a7aa8eaa78cc9605fcccda6d5
2	manager_anna	$2b$12$LJ3m4...hash...	anna@orderflow.ru	manager	Петрова Анна Сергеевна	2026-05-14 11:04:56.499824	\N
\.


--
-- Name: categories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.categories_id_seq', 3, true);


--
-- Name: order_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.order_items_id_seq', 6, true);


--
-- Name: order_status_history_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.order_status_history_id_seq', 12, true);


--
-- Name: orders_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.orders_id_seq', 4, true);


--
-- Name: products_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.products_id_seq', 3, true);


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.users_id_seq', 4, true);


--
-- Name: categories categories_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_name_key UNIQUE (name);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: order_items order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (id);


--
-- Name: order_status_history order_status_history_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_status_history
    ADD CONSTRAINT order_status_history_pkey PRIMARY KEY (id);


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: products products_sku_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_sku_key UNIQUE (sku);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- Name: idx_history_order_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_history_order_id ON public.order_status_history USING btree (order_id);


--
-- Name: idx_order_items_order_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_order_items_order_id ON public.order_items USING btree (order_id);


--
-- Name: idx_order_items_product_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_order_items_product_id ON public.order_items USING btree (product_id);


--
-- Name: idx_orders_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_status ON public.orders USING btree (status);


--
-- Name: idx_orders_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_user_id ON public.orders USING btree (user_id);


--
-- Name: idx_products_category_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_products_category_id ON public.products USING btree (category_id);


--
-- Name: orders trg_order_status_log; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_order_status_log AFTER UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.fn_log_order_status_change();


--
-- Name: orders trg_update_timestamp; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_update_timestamp BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();


--
-- Name: order_items order_items_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: order_items order_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE RESTRICT;


--
-- Name: order_status_history order_status_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_status_history
    ADD CONSTRAINT order_status_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: order_status_history order_status_history_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_status_history
    ADD CONSTRAINT order_status_history_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: orders orders_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: products products_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE RESTRICT;


--
-- PostgreSQL database dump complete
--

\unrestrict OOioTUh74dHfjzfiATAekRIpTR03dT2vWtRIB6TT5wztdq4liw37UeKAN2uSf40

