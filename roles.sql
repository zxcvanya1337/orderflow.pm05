-- ============================================================
-- Roles & Users (Роли и Пользователи)
-- ============================================================

-- 1. Создание групповых ролей (без права входа)
CREATE ROLE IF NOT EXISTS role_readonly;
CREATE ROLE IF NOT EXISTS role_manager;
CREATE ROLE IF NOT EXISTS role_admin;

-- 2. Назначение привилегий ролям

-- --- Роль: Только чтение (Аналитик) ---
GRANT USAGE ON SCHEMA public TO role_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO role_readonly;
-- Доступ к будущим таблицам (опционально)
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO role_readonly;

-- --- Роль: Менеджер/Оператор ---
GRANT USAGE ON SCHEMA public TO role_manager;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO role_manager;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO role_manager;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO role_manager;

-- --- Роль: Администратор ---
GRANT ALL PRIVILEGES ON SCHEMA public TO role_admin;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO role_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO role_admin;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO role_admin;

-- 3. Создание пользователей (с правом входа) и добавление их в роли

-- Пользователь-аналитик
CREATE USER IF NOT EXISTS db_user_analyst WITH PASSWORD 'secure_password_1';
GRANT role_readonly TO db_user_analyst;

-- Пользователь-менеджер (для приложения)
CREATE USER IF NOT EXISTS db_user_app WITH PASSWORD 'secure_password_2';
GRANT role_manager TO db_user_app;

-- Пользователь-администратор
CREATE USER IF NOT EXISTS db_user_admin WITH PASSWORD 'secure_password_3';
GRANT role_admin TO db_user_admin;