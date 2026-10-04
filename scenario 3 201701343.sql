-- ICT371 PostgreSQL Scenario Assignment
-- Scenario 3: Student Hostel Room Allocation
-- Student Number: 201701343

-- 1. TABLES AND DATA
DROP TABLE IF EXISTS allocations;
DROP TABLE IF EXISTS hostel_rooms;

CREATE TABLE hostel_rooms (
    room_id          SERIAL PRIMARY KEY,
    room_number      VARCHAR(10) NOT NULL UNIQUE,
    available_spaces INT NOT NULL CHECK (available_spaces >= 0)
);

CREATE TABLE allocations (
    allocation_id  SERIAL PRIMARY KEY,
    student_number VARCHAR(20) NOT NULL,
    room_id        INT NOT NULL REFERENCES hostel_rooms(room_id),
    status         VARCHAR(12) NOT NULL DEFAULT 'ALLOCATED'
                   CHECK (status IN ('ALLOCATED', 'COMPLETE'))
);

INSERT INTO hostel_rooms (room_number, available_spaces) VALUES
    ('A101', 4),
    ('A102', 1),
    ('B201', 0);

SELECT * FROM hostel_rooms ORDER BY room_id;

-- 2. IF / ELSIF / ELSE
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT room_number, available_spaces FROM hostel_rooms ORDER BY room_id LOOP
        IF rec.available_spaces = 0 THEN
            RAISE NOTICE 'Room %: FULL', rec.room_number;
        ELSIF rec.available_spaces = 1 THEN
            RAISE NOTICE 'Room %: ONE space left', rec.room_number;
        ELSE
            RAISE NOTICE 'Room %: SEVERAL spaces (%)', rec.room_number, rec.available_spaces;
        END IF;
    END LOOP;
END $$;

-- 3. WHILE loop and numeric FOR loop
DO $$
DECLARE
    v_day INT := 1;
BEGIN
    WHILE v_day <= 3 LOOP
        RAISE NOTICE 'Hostel inspection day %', v_day;
        v_day := v_day + 1;
    END LOOP;

    FOR n IN 1..3 LOOP
        RAISE NOTICE 'Room check %', n;
    END LOOP;
END $$;

-- 4. allocate_room PROCEDURE
CREATE OR REPLACE PROCEDURE allocate_room(p_room_id INT, p_student VARCHAR)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_student IS NULL OR btrim(p_student) = '' THEN
        RAISE EXCEPTION 'Invalid student number: it cannot be blank'
            USING ERRCODE = '22023';
    END IF;

    SELECT available_spaces INTO v_available
    FROM hostel_rooms WHERE room_id = p_room_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Room % does not exist. Allocation not recorded.', p_room_id;
        RETURN;
    END IF;

    IF v_available < 1 THEN
        RAISE NOTICE 'Allocation REJECTED for student %: room % is full.', p_student, p_room_id;
        RETURN;
    END IF;

    UPDATE hostel_rooms SET available_spaces = available_spaces - 1
    WHERE room_id = p_room_id;

    INSERT INTO allocations (student_number, room_id)
    VALUES (p_student, p_room_id);

    RAISE NOTICE 'Allocation RECORDED: student % allocated to room %.', p_student, p_room_id;
END $$;

-- 5. CALL: two valid allocations and one to a full room
CALL allocate_room(1, '2024001');   -- valid
CALL allocate_room(2, '2024002');   -- valid (room A102 becomes full)
CALL allocate_room(3, '2024003');   -- room B201 is full

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- 6. check_out PROCEDURE
CREATE OR REPLACE PROCEDURE check_out(p_allocation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_room_id INT;
    v_status  VARCHAR(12);
BEGIN
    SELECT room_id, status INTO v_room_id, v_status
    FROM allocations WHERE allocation_id = p_allocation_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Allocation % does not exist.', p_allocation_id;
        RETURN;
    END IF;

    IF v_status = 'COMPLETE' THEN
        RAISE NOTICE 'Allocation % is already complete. No extra space freed.', p_allocation_id;
        RETURN;
    END IF;

    UPDATE allocations SET status = 'COMPLETE' WHERE allocation_id = p_allocation_id;
    UPDATE hostel_rooms SET available_spaces = available_spaces + 1 WHERE room_id = v_room_id;

    RAISE NOTICE 'Allocation % checked out. One space freed in room %.', p_allocation_id, v_room_id;
END $$;

CALL check_out(2);   -- first call: frees a space
CALL check_out(2);   -- second call: must not free another

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- 7. EXPLICIT CURSOR: full or nearly full rooms (1 space or fewer)
DO $$
DECLARE
    cur_rooms CURSOR FOR
        SELECT room_number, available_spaces
        FROM hostel_rooms WHERE available_spaces <= 1 ORDER BY room_number;
    v_room VARCHAR; v_spaces INT;
BEGIN
    OPEN cur_rooms;
    LOOP
        FETCH cur_rooms INTO v_room, v_spaces;
        EXIT WHEN NOT FOUND;
        IF v_spaces = 0 THEN
            RAISE NOTICE 'Room % is FULL', v_room;
        ELSE
            RAISE NOTICE 'Room % is NEARLY FULL (% space left)', v_room, v_spaces;
        END IF;
    END LOOP;
    CLOSE cur_rooms;
END $$;

-- 8. EXCEPTION: blank student number
DO $$
BEGIN
    CALL allocate_room(1, '   ');
EXCEPTION
    WHEN invalid_parameter_value THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- 9. FINAL RESULTS
SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;
