/* How many times was the app downloaded? */

SELECT COUNT(DISTINCT app_download_key) AS download_count
FROM app_downloads;

/* How many users signed up on the app?*/

SELECT COUNT(DISTINCT user_id) AS signup_count
FROM signups;

/* How many rides were requested through the app? */

SELECT COUNT(*) AS ride_request_count
FROM ride_requests;

/*  How many rides were requested and completed through the app?*/

SELECT
    COUNT(*) AS rides_requested,
    SUM(CASE WHEN dropoff_ts IS NOT NULL THEN 1 ELSE 0 END) AS rides_completed
FROM ride_requests;

/* How many rides were requested and how many unique users requested a ride?*/

SELECT
    COUNT(*) AS rides_requested,
    COUNT(DISTINCT user_id) AS unique_users_requesting_ride
FROM ride_requests;

/*  What is the average time of a ride from pick up to drop off?*/

SELECT AVG(dropoff_ts - pickup_ts) AS average_ride_time
FROM ride_requests
WHERE dropoff_ts IS NOT NULL AND pickup_ts IS NOT NULL;

/*  How many rides were accepted by a driver?*/

SELECT COUNT(*) AS accepted_ride_count
FROM ride_requests
WHERE accept_ts IS NOT NULL;

/*  How many rides did we successfully collect payments and how much was collected?*/

SELECT
    COUNT(DISTINCT ride_id) AS total_rides,
    CONCAT('$', ROUND(SUM(purchase_amount_usd)::numeric, 2)) AS total_payment_received
FROM
    transactions
WHERE
    charge_status = 'Approved';

/* How many ride requests happened on each platform?*/

SELECT
    ad.platform,
    COUNT(*) AS ride_request_count
FROM
    app_downloads ad
JOIN
    signups AS sg ON sg.session_id = ad.app_download_key
JOIN
    ride_requests rr ON rr.user_id = sg.user_id
GROUP BY
    ad.platform;

/* What is the drop-off from users signing up to users requesting a ride?*/

WITH signups AS (
  SELECT COUNT(DISTINCT user_id) AS signups_count
  FROM signups
),
requests AS (
  SELECT COUNT(DISTINCT user_id) AS requests_count
  FROM ride_requests
)
SELECT CONCAT(ROUND((1 - 1.0 * requests.requests_count / signups.signups_count) * 100, 2), '%') AS drop_off_percentage
FROM signups, requests;

-------------------------------------------------------------------------------------
/* What is the step by step conversion rate?*/

WITH funnel AS (
 SELECT
   'App_Downloads' AS step,
   COUNT(DISTINCT app_download_key) AS count
 FROM app_downloads
 UNION
 SELECT
   'Sign_Ups' AS step,
   COUNT(DISTINCT user_id) AS count
 FROM signups
 UNION
 SELECT
   'Ride_Requests' AS step,
   COUNT(DISTINCT user_id) AS count
 FROM ride_requests
 UNION
 SELECT
   'Completed_Rides' AS step,
   COUNT(DISTINCT user_id) AS count
 FROM ride_requests
 WHERE dropoff_ts IS NOT NULL
)
SELECT
 step,
 count,
 LAG(count) OVER (ORDER BY CASE
     WHEN step = 'App_Downloads' THEN 1
     WHEN step = 'Sign_Ups' THEN 2
     WHEN step = 'Ride_Requests' THEN 3
     WHEN step = 'Completed_Rides' THEN 4
     ELSE 5
   END) AS previous_count,
 CASE
   WHEN LAG(count) OVER (ORDER BY CASE
       WHEN step = 'App_Downloads' THEN 1
       WHEN step = 'Sign_Ups' THEN 2
       WHEN step = 'Ride_Requests' THEN 3
       WHEN step = 'Completed_Rides' THEN 4
       ELSE 5
   END) = 0 THEN 0
   ELSE ROUND(LEAST((count::numeric / LAG(count) OVER (ORDER BY CASE
       WHEN step = 'App_Downloads' THEN 1
       WHEN step = 'Sign_Ups' THEN 2
       WHEN step = 'Ride_Requests' THEN 3
       WHEN step = 'Completed_Rides' THEN 4
       ELSE 5
   END)) * 100, 100), 2)
 END AS conversion_rate
FROM funnel
ORDER BY
 CASE
   WHEN step = 'App_Downloads' THEN 1
   WHEN step = 'Sign_Ups' THEN 2
   WHEN step = 'Ride_Requests' THEN 3
   WHEN step = 'Completed_Rides' THEN 4
   ELSE 5
 END;

/*What steps of the funnel should we research and improve? Are there any specific drop-off points preventing users from completing their first ride? */

WITH funnel AS (
  SELECT
    'App_Downloads' AS step,
    COUNT(DISTINCT app_download_key) AS count
  FROM app_downloads
  UNION
  SELECT
    'Sign_Ups' AS step,
    COUNT(DISTINCT user_id) AS count
  FROM signups
  UNION
  SELECT
    'Ride_Requests' AS step,
    COUNT(DISTINCT user_id) AS count
  FROM ride_requests
  UNION
  SELECT
    'Completed_Rides' AS step,
    COUNT(DISTINCT user_id) AS count
  FROM ride_requests
  WHERE dropoff_ts IS NOT NULL
),
funnel_with_previous AS (
  SELECT
    step,
    count,
    LAG(count) OVER (ORDER BY CASE
        WHEN step = 'App_Downloads' THEN 1
        WHEN step = 'Sign_Ups' THEN 2
        WHEN step = 'Ride_Requests' THEN 3
        WHEN step = 'Completed_Rides' THEN 4
        ELSE 5
      END) AS previous_count
  FROM funnel
),
funnel_with_conversion AS (
  SELECT
    step,
    count,
    previous_count,
    CASE
      WHEN previous_count = 0 THEN 0
      ELSE ROUND(LEAST((count::numeric / previous_count) * 100, 100), 2)
    END AS conversion_rate
  FROM funnel_with_previous
)
SELECT
  step,
  count,
  previous_count,
  conversion_rate,
  CASE
    WHEN previous_count = 0 THEN 'N/A'
    ELSE CONCAT(ROUND(((previous_count - count::numeric) / previous_count) * 100, 2), '%')
  END AS drop_off_percentage
FROM funnel_with_conversion
ORDER BY
  CASE
    WHEN step = 'App_Downloads' THEN 1
    WHEN step = 'Sign_Ups' THEN 2
    WHEN step = 'Ride_Requests' THEN 3
    WHEN step = 'Completed_Rides' THEN 4
    ELSE 5
  END;

/*Metrocar currently supports 3 different platforms: ios, android, and web. To recommend where to focus our marketing budget for the upcoming year, what insights can we make based on the platform?*/

WITH app_downloads_count AS (
  SELECT
    platform,
    COUNT(*) AS app_downloads
  FROM
    app_downloads
  GROUP BY
    platform
),
signups_count AS (
  SELECT
    platform,
    COUNT(DISTINCT user_id) AS signups
  FROM
    signups
  GROUP BY
    platform
),
ride_requests_count AS (
  SELECT
    ad.platform,
    COUNT(*) AS ride_requests
  FROM
    app_downloads ad
    JOIN signups AS sg ON sg.session_id = ad.app_download_key
    JOIN ride_requests rr ON rr.user_id = sg.user_id
  GROUP BY
    ad.platform
),
completed_rides_count AS (
  SELECT
    ad.platform,
    COUNT(DISTINCT rr.user_id) AS completed_rides,
    SUM(t.purchase_amount_usd) AS total_payment_amount
  FROM
    app_downloads ad
    JOIN signups AS sg ON sg.session_id = ad.app_download_key
    JOIN ride_requests rr ON rr.user_id = sg.user_id
    JOIN transactions t ON rr.ride_id = t.ride_id
  WHERE
    rr.dropoff_ts IS NOT NULL
  GROUP BY
    ad.platform
)
SELECT
  ad.platform,
  COALESCE(app_downloads, 0) AS app_downloads,
  COALESCE(signups, 0) AS signups,
  COALESCE(ride_requests, 0) AS ride_requests,
  COALESCE(completed_rides, 0) AS completed_rides,
  COALESCE(total_payment_amount, 0) AS total_payment_amount
FROM
  app_downloads_count ad
  LEFT JOIN signups_count su ON ad.platform = su.platform
  LEFT JOIN ride_requests_count rr ON ad.platform = rr.platform
  LEFT JOIN completed_rides_count cr ON ad.platform = cr.platform;

/* What age groups perform best at each stage of our funnel? Which age group(s) likely contain our target customers?*/

select age_range, count(*)
from signups
GROUP BY age_range
order by age_range

----- to see the age_range and the no of ride count with respect to each age_range

WITH funnel AS (
  SELECT
    CASE
      WHEN signups.age_range IS NULL THEN 'GDPR data'
      WHEN signups.age_range = 'None' THEN 'GDPR data'
      ELSE signups.age_range
    END AS age_range,
    COUNT(DISTINCT app_downloads.app_download_key) AS app_downloads_count,
    COUNT(DISTINCT signups.user_id) AS sign_ups_count,
    COUNT(DISTINCT ride_requests.user_id) AS ride_requests_count,
    COUNT(DISTINCT CASE WHEN ride_requests.dropoff_ts IS NOT NULL THEN ride_requests.user_id END) AS completed_rides_count
  FROM app_downloads
  LEFT JOIN signups ON app_downloads.app_download_key = signups.session_id
  LEFT JOIN ride_requests ON signups.user_id = ride_requests.user_id
  WHERE signups.age_range IS NOT NULL
  GROUP BY age_range
)
SELECT
  age_range,
  MAX(app_downloads_count) AS app_downloads_count,
  MAX(sign_ups_count) AS sign_ups_count,
  MAX(ride_requests_count) AS ride_requests_count,
  MAX(completed_rides_count) AS completed_rides_count
FROM funnel
GROUP BY age_range
ORDER BY
  CASE
    WHEN age_range = 'GDPR data' THEN 100
    ELSE CAST(SPLIT_PART(age_range, '-', 1) AS INT)
  END;

--This below code calculates the conversion rates for each step within each age_range and includes a row showing the conversion rate for each step.--

WITH funnel AS (
  SELECT
    CASE
      WHEN signups.age_range IS NULL THEN 'GDPR data'
      WHEN signups.age_range = 'None' THEN 'GDPR data'
      ELSE signups.age_range
    END AS age_range,
    COUNT(DISTINCT app_downloads.app_download_key) AS app_downloads_count,
    COUNT(DISTINCT signups.user_id) AS sign_ups_count,
    COUNT(DISTINCT ride_requests.user_id) AS ride_requests_count,
    COUNT(DISTINCT CASE WHEN ride_requests.dropoff_ts IS NOT NULL THEN ride_requests.user_id END) AS completed_rides_count
  FROM app_downloads
  LEFT JOIN signups ON app_downloads.app_download_key = signups.session_id
  LEFT JOIN ride_requests ON signups.user_id = ride_requests.user_id
  WHERE signups.age_range IS NOT NULL
  GROUP BY age_range
),
conversion_rates AS (
  SELECT
    age_range,
    app_downloads_count,
    sign_ups_count,
    ride_requests_count,
    completed_rides_count,
    0.00 AS downloads_conv_rate,
    CASE
      WHEN app_downloads_count = 0 THEN 0.00
      ELSE ROUND((sign_ups_count::numeric / app_downloads_count::numeric) * 100, 2)
    END AS signups_conv_rate,
    CASE
      WHEN sign_ups_count = 0 THEN 0.00
      ELSE ROUND((ride_requests_count::numeric / sign_ups_count::numeric) * 100, 2)
    END AS requests_conv_rate,
    CASE
      WHEN ride_requests_count = 0 THEN 0.00
      ELSE ROUND((completed_rides_count::numeric / ride_requests_count::numeric) * 100, 2)
    END AS rides_conv_rate
  FROM funnel
)
SELECT
  age_range,
  app_downloads_count AS downloads,
  downloads_conv_rate AS downloads_conv_rate,
  sign_ups_count AS signups,
  signups_conv_rate AS signups_conv_rate,
  ride_requests_count AS requests,
  requests_conv_rate AS requests_conv_rate,
  completed_rides_count AS rides,
  rides_conv_rate AS rides_conv_rate
FROM conversion_rates
ORDER BY
  CASE
    WHEN age_range = 'GDPR data' THEN 100
    ELSE CAST(SPLIT_PART(age_range, '-', 1) AS INT)
  END;


/* Surge pricing is the practice of increasing the price of goods or services when there is the greatest demand for them. If we want to adopt a price-surging strategy, what does the distribution of ride requests look like throughout the day?*/

WITH ride_requests_distribution AS (
  SELECT
    EXTRACT(HOUR FROM request_ts) AS hour_of_day,
    COUNT(*) AS request_count
  FROM
    ride_requests
  GROUP BY
    hour_of_day
  ORDER BY
    hour_of_day
)
SELECT
  hour_of_day,
  request_count
FROM
  ride_requests_distribution;

--the above code give each hour ride count while the below code has made bucket of hours as peak/moderate/heavy and casual ride hours--

WITH ride_requests_distribution AS (
  SELECT
    EXTRACT(HOUR FROM request_ts) AS hour_of_day,
    COUNT(*) AS request_count
  FROM
    ride_requests
  GROUP BY
    hour_of_day
  ORDER BY
    hour_of_day
),
ride_request_segments AS (
  SELECT
    hour_of_day,
    request_count,
    CASE
      WHEN hour_of_day <= 7 THEN 'Morning-(0:00 - 7:00 hours) Less rush'
      WHEN hour_of_day >= 7 AND hour_of_day <= 9 THEN 'Morning-(8:00 - 9:00 hours) peak hours'
      WHEN hour_of_day >= 9 AND hour_of_day <= 15 THEN 'Afternoon-(10:00 - 15:00 hours) moderate rush'
      WHEN hour_of_day > 15 AND hour_of_day <= 19 THEN 'Evening-(16:00 - 19:00 hours) Heavy rush'
      ELSE 'Late Evening-(19:00 - 00:00 hours) Casual rides'
    END AS request_segment
  FROM
    ride_requests_distribution
)
SELECT
  request_segment,
  SUM(request_count) AS total_request_count,
  ROUND(AVG(request_count),2) AS average_per_hour_ride
FROM
  ride_request_segments
GROUP BY
  request_segment
ORDER BY
  MIN(hour_of_day);

/* What part of our funnel has the lowest conversion rate? What can we do to improve this part of the funnel?*/

WITH funnel AS (
 SELECT
   'App_Downloads' AS step,
   COUNT(DISTINCT app_download_key) AS count
 FROM app_downloads
 UNION
 SELECT
   'Sign_Ups' AS step,
   COUNT(DISTINCT user_id) AS count
 FROM signups
 UNION
 SELECT
   'Ride_Requests' AS step,
   COUNT(DISTINCT user_id) AS count
 FROM ride_requests
 UNION
 SELECT
   'Completed_Rides' AS step,
   COUNT(DISTINCT user_id) AS count
 FROM ride_requests
 WHERE dropoff_ts IS NOT NULL
)
SELECT
 step,
 count,
 LAG(count) OVER (ORDER BY CASE
     WHEN step = 'App_Downloads' THEN 1
     WHEN step = 'Sign_Ups' THEN 2
     WHEN step = 'Ride_Requests' THEN 3
     WHEN step = 'Completed_Rides' THEN 4
     ELSE 5
   END) AS previous_count,
 CASE
   WHEN LAG(count) OVER (ORDER BY CASE
       WHEN step = 'App_Downloads' THEN 1
       WHEN step = 'Sign_Ups' THEN 2
       WHEN step = 'Ride_Requests' THEN 3
       WHEN step = 'Completed_Rides' THEN 4
       ELSE 5
   END) = 0 THEN 0
   ELSE ROUND(LEAST((count::numeric / LAG(count) OVER (ORDER BY CASE
       WHEN step = 'App_Downloads' THEN 1
       WHEN step = 'Sign_Ups' THEN 2
       WHEN step = 'Ride_Requests' THEN 3
       WHEN step = 'Completed_Rides' THEN 4
       ELSE 5
   END)) * 100, 100), 2)
 END AS conversion_rate
FROM funnel
ORDER BY
 CASE
   WHEN step = 'App_Downloads' THEN 1
   WHEN step = 'Sign_Ups' THEN 2
   WHEN step = 'Ride_Requests' THEN 3
   WHEN step = 'Completed_Rides' THEN 4
   ELSE 5
 END;

 /*How many unique users requested a ride through the Metrocar app? */

 SELECT COUNT(DISTINCT user_id) AS unique_users
FROM ride_requests;

/* How many unique users completed a ride through the Metrocar app?*/

SELECT COUNT(DISTINCT user_id) AS unique_users_completed
FROM ride_requests
WHERE dropoff_ts IS NOT NULL;

/* Of the users that signed up on the app, what percentage these users requested a ride?*/

WITH signed_up_users AS (
  SELECT COUNT(DISTINCT user_id) AS signed_up_count
  FROM signups
),
requested_users AS (
  SELECT COUNT(DISTINCT user_id) AS requested_count
  FROM ride_requests
)

SELECT
  CONCAT(ROUND((requested_count::numeric / signed_up_count::numeric) * 100, 1), '%') AS signup_ride_request_percentage_users
FROM
  signed_up_users, requested_users;

/* Of the users that signed up on the app, what percentage these users completed a ride?*/

WITH signed_up_users AS (
  SELECT COUNT(DISTINCT user_id) AS signed_up_count
  FROM signups
),
completed_users AS (
  SELECT COUNT(DISTINCT user_id) AS completed_count
  FROM ride_requests
  WHERE dropoff_ts IS NOT NULL
)

SELECT
  CONCAT(ROUND((completed_count::numeric / signed_up_count::numeric) * 100, 1), '%') AS signup_completed_percentage_users
FROM
  signed_up_users, completed_users;


/* Using the percent of previous approach, what are the user-level conversion rates for the first 3 stages of the funnel (app download to signup and signup to ride requested)?*/

WITH app_downloads AS (
  SELECT COUNT(DISTINCT app_download_key) AS app_downloads_count
  FROM app_downloads
),
sign_ups AS (
  SELECT COUNT(DISTINCT user_id) AS sign_ups_count
  FROM signups
),
ride_requests AS (
  SELECT COUNT(DISTINCT user_id) AS ride_requests_count
  FROM ride_requests
)

SELECT
  CONCAT(ROUND((sign_ups_count::numeric / app_downloads_count::numeric) * 100, 1), '%') AS conversion_rate_app_signup,
  CONCAT(ROUND((ride_requests_count::numeric / sign_ups_count::numeric) * 100, 1), '%') AS conversion_rate_signup_ride
FROM
  app_downloads, sign_ups, ride_requests;

-- other way to get the output visuals--

WITH funnel AS (
  SELECT
    'App_Downloads' AS step,
    COUNT(DISTINCT app_download_key) AS count
  FROM app_downloads
  UNION
  SELECT
    'Sign_Ups' AS step,
    COUNT(DISTINCT user_id) AS count
  FROM signups
  UNION
  SELECT
    'Ride_Requests' AS step,
    COUNT(DISTINCT user_id) AS count
  FROM ride_requests
),
conversion_rates AS (
  SELECT
    step,
    count,
    LAG(count) OVER (ORDER BY step_order) AS previous_count,
    CASE
      WHEN LAG(count) OVER (ORDER BY step_order) = 0 THEN 0
      ELSE ROUND((count::numeric / LAG(count) OVER (ORDER BY step_order)) * 100, 1)
    END AS conversion_rate
  FROM (
    SELECT
      step,
      count,
      ROW_NUMBER() OVER (ORDER BY CASE
          WHEN step = 'App_Downloads' THEN 1
          WHEN step = 'Sign_Ups' THEN 2
          WHEN step = 'Ride_Requests' THEN 3
        END) AS step_order
    FROM funnel
  ) subquery
)
SELECT
  step,
  CONCAT(conversion_rate, '%') AS conversion_rate
FROM
  conversion_rates
WHERE
  step IN ('App_Downloads', 'Sign_Ups', 'Ride_Requests');


/* Using the percent of top approach, what are the user-level conversion rates for the first 3 stages of the funnel (app download to signup and signup to ride requested)?*/

WITH funnel AS (
  SELECT
    'App_Downloads' AS step,
    COUNT(DISTINCT app_download_key) AS count
  FROM app_downloads
  UNION
  SELECT
    'Sign_Ups' AS step,
    COUNT(DISTINCT user_id) AS count
  FROM signups
  UNION
  SELECT
    'Ride_Requests' AS step,
    COUNT(DISTINCT user_id) AS count
  FROM ride_requests
),
conversion_rates AS (
  SELECT
    step,
    count,
    MAX(count) OVER (ORDER BY step_order) AS max_count,
    CASE
      WHEN MAX(count) OVER (ORDER BY step_order) = 0 THEN 0
      ELSE ROUND((count::numeric / MAX(count) OVER (ORDER BY step_order)) * 100, 1)
    END AS conversion_rate
  FROM (
    SELECT
      step,
      count,
      ROW_NUMBER() OVER (ORDER BY CASE
          WHEN step = 'App_Downloads' THEN 1
          WHEN step = 'Sign_Ups' THEN 2
          WHEN step = 'Ride_Requests' THEN 3
        END) AS step_order
    FROM funnel
  ) subquery
)
SELECT
  step,
  CONCAT(conversion_rate, '%') AS conversion_rate
FROM
  conversion_rates
WHERE
  step IN ('App_Downloads', 'Sign_Ups', 'Ride_Requests');

--Using first_value() for percent of top--

WITH funnel AS (
  SELECT
    'App_Downloads' AS step,
    COUNT(DISTINCT app_download_key) AS count
  FROM app_downloads
  UNION ALL
  SELECT
    'Sign_Ups' AS step,
    COUNT(DISTINCT user_id) AS count
  FROM signups
  UNION ALL
  SELECT
    'Ride_Requests' AS step,
    COUNT(DISTINCT user_id) AS count
  FROM ride_requests
),
conversion_rates AS (
  SELECT
    step,
    count,
    (count::numeric / FIRST_VALUE(count) OVER (ORDER BY step_order)) * 100 AS conversion_rate
  FROM (
    SELECT
      step,
      count,
      ROW_NUMBER() OVER (ORDER BY CASE
          WHEN step = 'App_Downloads' THEN 1
          WHEN step = 'Sign_Ups' THEN 2
          WHEN step = 'Ride_Requests' THEN 3
        END) AS step_order
    FROM funnel
  ) subquery
)
SELECT
  step,
  CONCAT(ROUND(conversion_rate, 1), '%') AS conversion_rate
FROM
  conversion_rates
WHERE
  step IN ('App_Downloads', 'Sign_Ups', 'Ride_Requests');

/* Using the percent of previous approach, what are the user-level conversion rates for the following 3 stages of the funnel? 1. signup, 2. ride requested, 3. ride completed*/

WITH funnel AS (
  SELECT
    'Signup' AS step,
    COUNT(DISTINCT user_id) AS count
  FROM signups
  UNION ALL
  SELECT
    'Ride_Requested' AS step,
    COUNT(DISTINCT user_id) AS count
  FROM ride_requests
  UNION ALL
  SELECT
    'Ride_Completed' AS step,
    COUNT(DISTINCT user_id) AS count
  FROM ride_requests
  WHERE dropoff_ts IS NOT NULL
),
conversion_rates AS (
  SELECT
    step,
    count,
    LAG(count) OVER (ORDER BY step_order) AS previous_count,
    CASE
      WHEN LAG(count) OVER (ORDER BY step_order) = 0 THEN 0
      ELSE ROUND((count::numeric / LAG(count) OVER (ORDER BY step_order)) * 100, 1)
    END AS conversion_rate
  FROM (
    SELECT
      step,
      count,
      ROW_NUMBER() OVER (ORDER BY CASE
          WHEN step = 'Signup' THEN 1
          WHEN step = 'Ride_Requested' THEN 2
          WHEN step = 'Ride_Completed' THEN 3
        END) AS step_order
    FROM funnel
  ) subquery
)
SELECT
  step,
  CONCAT(conversion_rate, '%') AS conversion_rate
FROM
  conversion_rates
WHERE
  step IN ('Signup', 'Ride_Requested', 'Ride_Completed');

/* Using the percent of top approach, what are the user-level conversion rates for the following 3 stages of the funnel? 1. signup, 2. ride requested, 3. ride completed (hint: signup is the top of this funnel)*/

WITH funnel AS (
  SELECT
    'Sign_Ups' AS step,
    COUNT(DISTINCT user_id) AS count
  FROM signups
  UNION ALL
  SELECT
    'Ride_Requests' AS step,
    COUNT(DISTINCT user_id) AS count
  FROM ride_requests
  UNION ALL
  SELECT
    'Ride_Completed' AS step,
    COUNT(DISTINCT user_id) AS count
  FROM ride_requests
  WHERE dropoff_ts IS NOT NULL
),
conversion_rates AS (
  SELECT
    step,
    count,
    (count::numeric / FIRST_VALUE(count) OVER (ORDER BY step_order)) * 100 AS conversion_rate
  FROM (
    SELECT
      step,
      count,
      ROW_NUMBER() OVER (ORDER BY CASE
          WHEN step = 'Sign_Ups' THEN 1
          WHEN step = 'Ride_Requests' THEN 2
          WHEN step = 'Ride_Completed' THEN 3
        END) AS step_order
    FROM funnel
  ) subquery
)
SELECT
  step,
  CONCAT(ROUND(conversion_rate, 1), '%') AS conversion_rate
FROM
  conversion_rates
WHERE
  step IN ('Sign_Ups', 'Ride_Requests', 'Ride_Completed');

/* Count of users in each step with percentage over total*/

WITH funnel AS (
  SELECT
    'App_Downloads' AS step,
    COUNT(DISTINCT app_download_key) AS count
  FROM app_downloads
  UNION ALL
  SELECT
    'Sign_Ups' AS step,
    COUNT(DISTINCT CAST(user_id AS TEXT)) AS count
  FROM signups
  UNION ALL
  SELECT
    'Ride_Requests' AS step,
    COUNT(DISTINCT CAST(user_id AS TEXT)) AS count
  FROM ride_requests
  UNION ALL
  SELECT
    'Completed_Rides' AS step,
    COUNT(DISTINCT CAST(user_id AS TEXT)) AS count
  FROM ride_requests
  WHERE dropoff_ts IS NOT NULL
),
total_users AS (
  SELECT COUNT(DISTINCT app_download_key) AS total_count
  FROM (
    SELECT CAST(app_download_key AS TEXT) FROM app_downloads
    UNION
    SELECT CAST(session_id AS TEXT) FROM signups
    UNION
    SELECT CAST(user_id AS TEXT) FROM ride_requests
  ) subquery
)
SELECT
  funnel.step,
  funnel.count,
  ROUND((funnel.count::numeric / total_users.total_count::numeric) * 100, 2) AS percentage_share
FROM
  funnel, total_users;
