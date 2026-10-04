-- ICT371 PostgreSQL Scenario Assignment
-- Scenario 1: University Library Book Loans
-- Student Number: 201701343

-- 1. TABLES AND DATA
DROP TABLE IF EXISTS book_loans;
DROP TABLE IF EXISTS books;

CREATE TABLE books (
    book_id          SERIAL PRIMARY KEY,
    title            VARCHAR(150) NOT NULL,
    author           VARCHAR(100) NOT NULL,
    available_copies INT NOT NULL CHECK (available_copies >= 0)
);

CREATE TABLE book_loans (
    loan_id        SERIAL PRIMARY KEY,
    book_id        INT NOT NULL REFERENCES books(book_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL CHECK (quantity > 0),
    loan_status    VARCHAR(10) NOT NULL DEFAULT 'BORROWED'
                   CHECK (loan_status IN ('BORROWED', 'RETURNED')),
    loan_date      DATE NOT NULL DEFAULT CURRENT_DATE
);

INSERT INTO books (title, author, available_copies) VALUES
    ('Database System Concepts',    'Silberschatz', 5),
    ('Introduction to Algorithms',  'Cormen',       2),
    ('Discrete Mathematics',        'Rosen',        0);

SELECT * FROM books ORDER BY book_id;

-- 2. IF / ELSIF / ELSE
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT title, available_copies FROM books ORDER BY book_id LOOP
        IF rec.available_copies = 0 THEN
            RAISE NOTICE '%: UNAVAILABLE (% copies)', rec.title, rec.available_copies;
        ELSIF rec.available_copies <= 2 THEN
            RAISE NOTICE '%: LOW on copies (% left)', rec.title, rec.available_copies;
        ELSE
            RAISE NOTICE '%: SUFFICIENTLY STOCKED (% copies)', rec.title, rec.available_copies;
        END IF;
    END LOOP;
END $$;

-- 3. WHILE loop and numeric FOR loop
DO $$
DECLARE
    v_counter INT := 1;
BEGIN
    WHILE v_counter <= 3 LOOP
        RAISE NOTICE 'Overdue reminder number %', v_counter;
        v_counter := v_counter + 1;
    END LOOP;

    FOR shelf IN 1..3 LOOP
        RAISE NOTICE 'Library shelf number %', shelf;
    END LOOP;
END $$;

-- 4. borrow_book PROCEDURE
CREATE OR REPLACE PROCEDURE borrow_book(p_book_id INT, p_student VARCHAR, p_qty INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: % (must be greater than zero)', p_qty
            USING ERRCODE = '22023';
    END IF;

    SELECT available_copies INTO v_available
    FROM books WHERE book_id = p_book_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Book % does not exist. Loan not recorded.', p_book_id;
        RETURN;
    END IF;

    IF v_available < p_qty THEN
        RAISE NOTICE 'Loan REJECTED for student %: requested %, only % available.',
                     p_student, p_qty, v_available;
        RETURN;
    END IF;

    UPDATE books SET available_copies = available_copies - p_qty
    WHERE book_id = p_book_id;

    INSERT INTO book_loans (book_id, student_number, quantity)
    VALUES (p_book_id, p_student, p_qty);

    RAISE NOTICE 'Loan RECORDED: student % borrowed % copy/copies of book %.',
                 p_student, p_qty, p_book_id;
END $$;

-- 5. CALL borrow_book: two valid loans and one exceeding available copies
CALL borrow_book(1, '2024001', 2);   -- valid
CALL borrow_book(2, '2024002', 1);   -- valid
CALL borrow_book(2, '2024003', 5);   -- exceeds (only 1 copy left)

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- 6. return_book PROCEDURE
CREATE OR REPLACE PROCEDURE return_book(p_loan_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_book_id INT;
    v_qty     INT;
    v_status  VARCHAR(10);
BEGIN
    SELECT book_id, quantity, loan_status INTO v_book_id, v_qty, v_status
    FROM book_loans WHERE loan_id = p_loan_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Loan % does not exist.', p_loan_id;
        RETURN;
    END IF;

    IF v_status = 'RETURNED' THEN
        RAISE NOTICE 'Loan % was already returned. Copies NOT restored again.', p_loan_id;
        RETURN;
    END IF;

    UPDATE book_loans SET loan_status = 'RETURNED' WHERE loan_id = p_loan_id;
    UPDATE books SET available_copies = available_copies + v_qty WHERE book_id = v_book_id;

    RAISE NOTICE 'Loan % returned. % copy/copies restored to book %.', p_loan_id, v_qty, v_book_id;
END $$;

CALL return_book(1);   -- first call: restores copies
CALL return_book(1);   -- second call: must not restore again

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- 7. EXPLICIT CURSOR: books with few copies remaining (3 or fewer)
DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT book_id, title, available_copies
        FROM books WHERE available_copies <= 3 ORDER BY available_copies;
    v_id INT; v_title VARCHAR; v_copies INT;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO v_id, v_title, v_copies;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few copies: [%] % - % left', v_id, v_title, v_copies;
    END LOOP;
    CLOSE cur_low;
END $$;

-- 8. EXCEPTION: borrow zero copies
DO $$
BEGIN
    CALL borrow_book(1, '2024004', 0);
EXCEPTION
    WHEN invalid_parameter_value THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- 9. FINAL RESULTS
SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;
