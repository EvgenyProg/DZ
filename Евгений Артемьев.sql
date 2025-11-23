-- Домашнее задание по базам данных
-- Вариант: PostgreSQL + CSV-файлы

-- ================================
-- ШАГ 1. СОЗДАНИЕ ТАБЛИЦ
-- ================================

DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS product;
DROP TABLE IF EXISTS customer;

-- Таблица клиентов
CREATE TABLE customer (
    customer_id           INTEGER PRIMARY KEY,
    first_name            TEXT,
    last_name             TEXT,
    gender                TEXT,
    DOB                   DATE,
    job_title             TEXT,
    job_industry_category TEXT,
    wealth_segment        TEXT,
    deceased_indicator    TEXT,
    owns_car              TEXT,
    address               TEXT,
    postcode              INTEGER,
    state                 TEXT,
    country               TEXT,
    property_valuation    INTEGER
);

-- Таблица продуктов
CREATE TABLE product (
    product_id     INTEGER PRIMARY KEY,
    brand          TEXT,
    product_line   TEXT,
    product_class  TEXT,
    product_size   TEXT,
    list_price     NUMERIC,
    standard_cost  NUMERIC
);

-- Таблица заказов
CREATE TABLE orders (
    order_id      INTEGER PRIMARY KEY,
    customer_id   INTEGER REFERENCES customer(customer_id),
    order_date    DATE,
    online_order  BOOLEAN,
    order_status  TEXT
);

-- Таблица позиций в заказах
CREATE TABLE order_items (
    order_item_id               INTEGER PRIMARY KEY,
    order_id                    INTEGER REFERENCES orders(order_id),
    product_id                  INTEGER REFERENCES product(product_id),
    quantity                    INTEGER,
    item_list_price_at_sale     NUMERIC,
    item_standard_cost_at_sale  NUMERIC
);

-- Загрузка данных из CSV может выглядеть так (пути заменить на свои):
-- Для customer.csv (разделитель ';'):
-- COPY customer
-- FROM '/path/to/customer.csv'
-- WITH (FORMAT csv, HEADER true, DELIMITER ';');

-- Для остальных файлов (если разделитель запятая):
-- COPY product
-- FROM '/path/to/product.csv'
-- WITH (FORMAT csv, HEADER true);

-- COPY orders
-- FROM '/path/to/orders.csv'
-- WITH (FORMAT csv, HEADER true);

-- COPY order_items
-- FROM '/path/to/order_items.csv'
-- WITH (FORMAT csv, HEADER true);



-- ================================
-- ШАГ 2. ЗАПРОСЫ
-- ================================

-- 1) Уникальные бренды, у которых:
--    - есть хотя бы один продукт со standard_cost > 1500
--    - суммарные продажи (quantity) по всем продуктам бренда >= 1000

SELECT
    p.brand
FROM product p
JOIN order_items oi ON oi.product_id = p.product_id
GROUP BY p.brand
HAVING
    MAX(p.standard_cost) > 1500
    AND SUM(oi.quantity) >= 1000
ORDER BY p.brand;



-- 2) Для каждого дня с 2017-04-01 по 2017-04-09:
--    - количество подтвержденных онлайн-заказов
--    - количество уникальных клиентов в этих заказах
--    (предполагаем, что подтвержденный статус = 'Approved')

SELECT
    d::date AS day,
    COUNT(o.order_id) AS confirmed_online_orders,
    COUNT(DISTINCT o.customer_id) AS unique_customers
FROM generate_series('2017-04-01'::date, '2017-04-09'::date, '1 day') AS d
LEFT JOIN orders o
    ON o.order_date = d::date
   AND o.online_order = TRUE
   AND o.order_status = 'Approved'
GROUP BY d
ORDER BY day;



-- 3) Профессии клиентов:
--    - из IT, где job_title начинается с 'Senior'
--    - из Financial Services, где job_title начинается с 'Lead'
--    Для обеих групп возраст > 35 лет.
--    Объединяем через UNION ALL.

SELECT
    customer_id,
    first_name,
    last_name,
    job_title,
    job_industry_category
FROM customer
WHERE
    job_industry_category = 'IT'
    AND job_title LIKE 'Senior%%'
    AND date_part('year', age(current_date, DOB)) > 35

UNION ALL

SELECT
    customer_id,
    first_name,
    last_name,
    job_title,
    job_industry_category
FROM customer
WHERE
    job_industry_category = 'Financial Services'
    AND job_title LIKE 'Lead%%'
    AND date_part('year', age(current_date, DOB)) > 35
ORDER BY job_industry_category, last_name, first_name;



-- 4) Бренды, которые покупали клиенты из Financial Services,
--    но НЕ покупали клиенты из IT.

-- Бренды, купленные клиентами из Financial Services
WITH fs_brands AS (
    SELECT DISTINCT p.brand
    FROM customer c
    JOIN orders o       ON o.customer_id = c.customer_id
    JOIN order_items oi ON oi.order_id = o.order_id
    JOIN product p      ON p.product_id = oi.product_id
    WHERE c.job_industry_category = 'Financial Services'
),
it_brands AS (
    SELECT DISTINCT p.brand
    FROM customer c
    JOIN orders o       ON o.customer_id = c.customer_id
    JOIN order_items oi ON oi.order_id = o.order_id
    JOIN product p      ON p.product_id = oi.product_id
    WHERE c.job_industry_category = 'IT'
)
SELECT brand
FROM fs_brands
WHERE brand NOT IN (SELECT brand FROM it_brands)
ORDER BY brand;



-- 5) Топ-10 клиентов по количеству онлайн-заказов брендов
--    Giant Bicycles, Norco Bicycles, Trek Bicycles,
--    при условии, что:
--    - клиент активен (deceased_indicator <> 'Y')
--    - property_valuation > среднего по его штату

WITH customers_with_avg AS (
    SELECT
        c.*,
        AVG(c.property_valuation) OVER (PARTITION BY c.state) AS avg_state_valuation
    FROM customer c
),
filtered_customers AS (
    SELECT
        cwa.*
    FROM customers_with_avg cwa
    WHERE
        (cwa.deceased_indicator IS NULL OR cwa.deceased_indicator <> 'Y')
        AND cwa.property_valuation > cwa.avg_state_valuation
),
online_brand_orders AS (
    SELECT
        o.customer_id,
        COUNT(DISTINCT o.order_id) AS online_orders_cnt
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    JOIN product p      ON p.product_id = oi.product_id
    WHERE
        o.online_order = TRUE
        AND o.order_status = 'Approved'
        AND p.brand IN ('Giant Bicycles', 'Norco Bicycles', 'Trek Bicycles')
    GROUP BY o.customer_id
)
SELECT
    fc.customer_id,
    fc.first_name,
    fc.last_name,
    oba.online_orders_cnt
FROM filtered_customers fc
JOIN online_brand_orders oba ON oba.customer_id = fc.customer_id
ORDER BY oba.online_orders_cnt DESC, fc.customer_id
LIMIT 10;



-- 6) Клиенты, у которых НЕТ подтвержденных онлайн-заказов за последний год,
--    но они владеют автомобилем и их wealth_segment <> 'Mass Customer'.

-- Под "последний год" здесь понимается период [current_date - 1 year, current_date].

SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    c.wealth_segment,
    c.owns_car
FROM customer c
WHERE
    c.owns_car IN ('Y', 'Yes', 'True', 'TRUE', 'T')  -- в зависимости от формата данных
    AND c.wealth_segment <> 'Mass Customer'
    AND NOT EXISTS (
        SELECT 1
        FROM orders o
        WHERE
            o.customer_id = c.customer_id
            AND o.online_order = TRUE
            AND o.order_status = 'Approved'
            AND o.order_date >= current_date - INTERVAL '1 year'
    )
ORDER BY c.last_name, c.first_name;



-- 7) Клиенты из сферы 'IT', которые купили 2 из 5 самых дорогих
--    (по list_price) продуктов в линейке product_line = 'Road'.

WITH top5_road_products AS (
    SELECT product_id
    FROM product
    WHERE product_line = 'Road'
    ORDER BY list_price DESC
    LIMIT 5
),
it_customers_road AS (
    SELECT
        c.customer_id,
        c.first_name,
        c.last_name,
        COUNT(DISTINCT oi.product_id) AS cnt_top_products
    FROM customer c
    JOIN orders o       ON o.customer_id = c.customer_id
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE
        c.job_industry_category = 'IT'
        AND oi.product_id IN (SELECT product_id FROM top5_road_products)
    GROUP BY c.customer_id, c.first_name, c.last_name
)
SELECT
    customer_id,
    first_name,
    last_name
FROM it_customers_road
WHERE cnt_top_products >= 2
ORDER BY customer_id;



-- 8) Клиенты из сфер IT или Health, которые:
--    - совершили не менее 3 подтвержденных заказов
--      в период с 2017-01-01 по 2017-03-01 (включительно)
--    - суммарный доход (quantity * item_list_price_at_sale) > 10000
--    Нужно вывести отдельно для IT и Health через UNION.

WITH orders_period AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.order_date,
        o.order_status
    FROM orders o
    WHERE
        o.order_status = 'Approved'
        AND o.order_date >= '2017-01-01'::date
        AND o.order_date <= '2017-03-01'::date
),
revenue_per_customer AS (
    SELECT
        op.customer_id,
        COUNT(DISTINCT op.order_id) AS orders_cnt,
        SUM(oi.quantity * oi.item_list_price_at_sale) AS total_revenue
    FROM orders_period op
    JOIN order_items oi ON oi.order_id = op.order_id
    GROUP BY op.customer_id
)
-- Группа IT
SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    c.job_industry_category AS industry
FROM revenue_per_customer r
JOIN customer c ON c.customer_id = r.customer_id
WHERE
    c.job_industry_category = 'IT'
    AND r.orders_cnt >= 3
    AND r.total_revenue > 10000

UNION

-- Группа Health
SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    c.job_industry_category AS industry
FROM revenue_per_customer r
JOIN customer c ON c.customer_id = r.customer_id
WHERE
    c.job_industry_category = 'Health'
    AND r.orders_cnt >= 3
    AND r.total_revenue > 10000

ORDER BY industry, last_name, first_name;
