-- ICT371 PostgreSQL Scenario Assignment
-- Scenario 2: Computer Laboratory Reservations
-- Student Number: 201701343

-- 1. TABLES AND DATA
DROP TABLE IF EXISTS reservations;
DROP TABLE IF EXISTS lab_sessions;

CREATE TABLE lab_sessions (
    session_id             SERIAL PRIMARY KEY,
    session_name           VARCHAR(100) NOT NULL,
    available_workstations INT NOT NULL CHECK (available_workstations >= 0)
);

CREATE TABLE reservations (
    reservation_id SERIAL PRIMARY KEY,
    session_id     INT NOT NULL REFERENCES lab_sessions(session_id),
    lecturer       VARCHAR(100) NOT NULL,
    workstations   INT NOT NULL CHECK (workstations > 0),
    status         VARCHAR(10) NOT NULL DEFAULT 'RESERVED'
                   CHECK (status IN ('RESERVED', 'CANCELLED'))
);

INSERT INTO lab_sessions (session_name, available_workstations) VALUES
    ('Monday 08:00 - Programming Lab',   30),
    ('Tuesday 10:00 - Networking Lab',    8),
    ('Wednesday 14:00 - Database Lab',    0);

SELECT * FROM lab_sessions ORDER BY session_id;

-- 2. IF / ELSIF / ELSE
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT session_name, available_workstations FROM lab_sessions ORDER BY session_id LOOP
        IF rec.available_workstations = 0 THEN
            RAISE NOTICE '%: FULL', rec.session_name;
        ELSIF rec.available_workstations <= 10 THEN
            RAISE NOTICE '%: NEARLY FULL (% left)', rec.session_name, rec.available_workstations;
        ELSE
            RAISE NOTICE '%: ENOUGH workstations (%)', rec.session_name, rec.available_workstations;
        END IF;
    END LOOP;
END $$;

-- 3. WHILE loop and numeric FOR loop
DO $$
DECLARE
    v_counter INT := 1;
BEGIN
    WHILE v_counter <= 3 LOOP
        RAISE NOTICE 'Session preparation reminder %', v_counter;
        v_counter := v_counter + 1;
    END LOOP;

    FOR n IN 1..3 LOOP
        RAISE NOTICE 'Workstation check %', n;
    END LOOP;
END $$;

-- 4. reserve_workstations PROCEDURE
CREATE OR REPLACE PROCEDURE reserve_workstations(p_session_id INT, p_lecturer VARCHAR, p_qty INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid number of workstations: % (must be greater than zero)', p_qty
            USING ERRCODE = '22023';
    END IF;

    SELECT available_workstations INTO v_available
    FROM lab_sessions WHERE session_id = p_session_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Session % does not exist. Reservation not recorded.', p_session_id;
        RETURN;
    END IF;

    IF v_available < p_qty THEN
        RAISE NOTICE 'Reservation REJECTED for %: requested %, only % available.',
                     p_lecturer, p_qty, v_available;
        RETURN;
    END IF;

    UPDATE lab_sessions SET available_workstations = available_workstations - p_qty
    WHERE session_id = p_session_id;

    INSERT INTO reservations (session_id, lecturer, workstations)
    VALUES (p_session_id, p_lecturer, p_qty);

    RAISE NOTICE 'Reservation RECORDED: % reserved % workstation(s) in session %.',
                 p_lecturer, p_qty, p_session_id;
END $$;

-- 5. CALL: two valid reservations and one exceeding capacity
CALL reserve_workstations(1, 'Dr. Mwansa', 20);   -- valid
CALL reserve_workstations(2, 'Mr. Banda', 5);     -- valid
CALL reserve_workstations(2, 'Ms. Phiri', 10);    -- exceeds (only 3 left)

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- 6. cancel_reservation PROCEDURE
CREATE OR REPLACE PROCEDURE cancel_reservation(p_reservation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_session_id INT;
    v_qty        INT;
    v_status     VARCHAR(10);
BEGIN
    SELECT session_id, workstations, status INTO v_session_id, v_qty, v_status
    FROM reservations WHERE reservation_id = p_reservation_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Reservation % does not exist.', p_reservation_id;
        RETURN;
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Reservation % is already cancelled. Workstations NOT released again.', p_reservation_id;
        RETURN;
    END IF;

    UPDATE reservations SET status = 'CANCELLED' WHERE reservation_id = p_reservation_id;
    UPDATE lab_sessions SET available_workstations = available_workstations + v_qty
    WHERE session_id = v_session_id;

    RAISE NOTICE 'Reservation % cancelled. % workstation(s) released to session %.',
                 p_reservation_id, v_qty, v_session_id;
END $$;

CALL cancel_reservation(1);   -- first call: releases workstations
CALL cancel_reservation(1);   -- second call: must not release again

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- 7. EXPLICIT CURSOR: sessions with few workstations remaining (5 or fewer)
DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT session_id, session_name, available_workstations
        FROM lab_sessions WHERE available_workstations <= 5 ORDER BY available_workstations;
    v_id INT; v_name VARCHAR; v_avail INT;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO v_id, v_name, v_avail;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few workstations: [%] % - % left', v_id, v_name, v_avail;
    END LOOP;
    CLOSE cur_low;
END $$;

-- 8. EXCEPTION: request zero workstations
DO $$
BEGIN
    CALL reserve_workstations(1, 'Dr. Mwansa', 0);
EXCEPTION
    WHEN invalid_parameter_value THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- 9. FINAL RESULTS
SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;
