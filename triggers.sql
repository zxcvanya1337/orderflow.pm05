-- ============================================================
-- Triggers (Триггеры)
-- ============================================================

-- 1. Триггер для автоматического логирования изменения статуса заказа
-- Срабатывает ПОСЛЕ обновления строки в таблице orders
CREATE TRIGGER trg_order_status_log 
AFTER UPDATE ON public.orders 
FOR EACH ROW 
EXECUTE FUNCTION public.fn_log_order_status_change();

-- 2. Триггер для автоматического обновления поля updated_at
-- Срабатывает ПЕРЕД обновлением строки в таблице orders
CREATE TRIGGER trg_update_timestamp 
BEFORE UPDATE ON public.orders 
FOR EACH ROW 
EXECUTE FUNCTION public.fn_set_updated_at();