-- ICT371 PostgreSQL Scenario Assignment
-- Scenario 4: Campus Clinic Medicine Dispensing
-- Student Number: 201701343

-- 1. TABLES AND DATA
DROP TABLE IF EXISTS dispensing_records;
DROP TABLE IF EXISTS medicines;

CREATE TABLE medicines (
    medicine_id    SERIAL PRIMARY KEY,
    medicine_name  VARCHAR(100) NOT NULL,
    stock_quantity INT NOT NULL CHECK (stock_quantity >= 0)
);

CREATE TABLE dispensing_records (
    record_id      SERIAL PRIMARY KEY,
    medicine_id    INT NOT NULL REFERENCES medicines(medicine_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL CHECK (quantity > 0),
    status         VARCHAR(10) NOT NULL DEFAULT 'DISPENSED'
                   CHECK (status IN ('DISPENSED', 'REVERSED'))
);

INSERT INTO medicines (medicine_name, stock_quantity) VALUES
    ('Paracetamol 500mg', 100),
    ('Amoxicillin 250mg',  18),
    ('Artemether-Lumefantrine', 0);

SELECT * FROM medicines ORDER BY medicine_id;

-- 2. IF / ELSIF / ELSE
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT medicine_name, stock_quantity FROM medicines ORDER BY medicine_id LOOP
        IF rec.stock_quantity = 0 THEN
            RAISE NOTICE '%: OUT OF STOCK', rec.medicine_name;
        ELSIF rec.stock_quantity < 20 THEN
            RAISE NOTICE '%: LOW on stock (%)', rec.medicine_name, rec.stock_quantity;
        ELSE
            RAISE NOTICE '%: SUFFICIENTLY STOCKED (%)', rec.medicine_name, rec.stock_quantity;
        END IF;
    END LOOP;
END $$;

-- 3. WHILE loop and numeric FOR loop
DO $$
DECLARE
    v_day INT := 1;
BEGIN
    WHILE v_day <= 3 LOOP
        RAISE NOTICE 'Stock review day %', v_day;
        v_day := v_day + 1;
    END LOOP;

    FOR n IN 1..3 LOOP
        RAISE NOTICE 'Shelf inspection %', n;
    END LOOP;
END $$;

-- 4. dispense_medicine PROCEDURE
CREATE OR REPLACE PROCEDURE dispense_medicine(p_medicine_id INT, p_student VARCHAR, p_qty INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock INT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid dispensing quantity: % (must be greater than zero)', p_qty
            USING ERRCODE = '22023';
    END IF;

    SELECT stock_quantity INTO v_stock
    FROM medicines WHERE medicine_id = p_medicine_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Medicine % does not exist. Nothing dispensed.', p_medicine_id;
        RETURN;
    END IF;

    IF v_stock < p_qty THEN
        RAISE NOTICE 'Dispensing REJECTED for student %: requested %, only % in stock.',
                     p_student, p_qty, v_stock;
        RETURN;
    END IF;

    UPDATE medicines SET stock_quantity = stock_quantity - p_qty
    WHERE medicine_id = p_medicine_id;

    INSERT INTO dispensing_records (medicine_id, student_number, quantity)
    VALUES (p_medicine_id, p_student, p_qty);

    RAISE NOTICE 'Dispensing RECORDED: % unit(s) of medicine % to student %.',
                 p_qty, p_medicine_id, p_student;
END $$;

-- 5. CALL: two valid quantities and one exceeding stock
CALL dispense_medicine(1, '2024001', 10);   -- valid
CALL dispense_medicine(2, '2024002', 3);    -- valid
CALL dispense_medicine(2, '2024003', 50);   -- exceeds stock

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;

-- 6. reverse_dispensing PROCEDURE
CREATE OR REPLACE PROCEDURE reverse_dispensing(p_record_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_medicine_id INT;
    v_qty         INT;
    v_status      VARCHAR(10);
BEGIN
    SELECT medicine_id, quantity, status INTO v_medicine_id, v_qty, v_status
    FROM dispensing_records WHERE record_id = p_record_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Dispensing record % does not exist.', p_record_id;
        RETURN;
    END IF;

    IF v_status = 'REVERSED' THEN
        RAISE NOTICE 'Record % is already reversed. Stock NOT restored again.', p_record_id;
        RETURN;
    END IF;

    UPDATE dispensing_records SET status = 'REVERSED' WHERE record_id = p_record_id;
    UPDATE medicines SET stock_quantity = stock_quantity + v_qty WHERE medicine_id = v_medicine_id;

    RAISE NOTICE 'Record % reversed. % unit(s) restored to medicine %.', p_record_id, v_qty, v_medicine_id;
END $$;

CALL reverse_dispensing(1);   -- first call: restores stock
CALL reverse_dispensing(1);   -- second call: must not restore again

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;

-- 7. EXPLICIT CURSOR: medicines below a low-stock threshold
DO $$
DECLARE
    v_threshold INT := 20;
    cur_low CURSOR (p_limit INT) FOR
        SELECT medicine_name, stock_quantity
        FROM medicines WHERE stock_quantity < p_limit ORDER BY stock_quantity;
    v_name VARCHAR; v_stock INT;
BEGIN
    OPEN cur_low(v_threshold);
    LOOP
        FETCH cur_low INTO v_name, v_stock;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Below threshold (%): % - % in stock', v_threshold, v_name, v_stock;
    END LOOP;
    CLOSE cur_low;
END $$;

-- 8. EXCEPTION: negative dispensing quantity
DO $$
BEGIN
    CALL dispense_medicine(1, '2024004', -5);
EXCEPTION
    WHEN invalid_parameter_value THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- 9. FINAL RESULTS
SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;
