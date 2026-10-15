# Lab 08 — CloudWatch Observability

## Objective

Build a practical observability lab on AWS using:

- AWS Lambda
- CloudWatch Logs
- CloudWatch Metrics
- CloudWatch Metric Filters
- CloudWatch Alarms
- CloudWatch Dashboards
- CloudWatch Logs Insights
- Terraform

The goal of this lab was to understand the difference between logs, metrics, alarms and dashboards, and how they work together to help detect and investigate application problems.

---

# Core Observability Model

The main concepts practiced in this lab were:

Logs
=
What exactly happened?

Metrics
=
How much / how often did it happen?

Alarms
=
When did the metric cross a threshold?

Dashboards
=
How can I visualize the system behavior?

Logs Insights
=
How can I search, filter and aggregate logs during troubleshooting?

Conceptually:

Application
   |
   +--> Logs
   |      |
   |      +--> Logs Insights
   |      |
   |      +--> Metric Filter
   |              |
   |              v
   |        Custom Metric
   |              |
   |              v
   |            Alarm
   |
   +--> Native AWS Metrics
          |
          v
        Alarm

Everything can be visualized in a CloudWatch Dashboard.

---

# Application

A simple AWS Lambda function was created to simulate three application behaviors:

success

warning

error

The function logs different messages depending on the event received.

Example:

mode = success

Result:

INFO
Application started

INFO
Execution mode: success

INFO
Execution completed successfully

---

mode = warning

Result:

WARNING
Simulated warning event

---

mode = error

Result:

ERROR
Simulated application failure

Exception:
Simulated application error

---

# Infrastructure

Terraform created the following resources:

- Lambda Function
- Lambda IAM Execution Role
- CloudWatch Log Group
- CloudWatch Metric Filter
- CloudWatch Custom Metric
- CloudWatch Warning Alarm
- CloudWatch Lambda Error Alarm
- CloudWatch Dashboard

Region:

us-east-1

---

# Lambda IAM Role

The Lambda function uses an IAM execution role.

The managed policy used was:

AWSLambdaBasicExecutionRole

This allows Lambda to send logs to CloudWatch Logs.

Conceptually:

Lambda
   |
   v
IAM Execution Role
   |
   v
CloudWatch Logs

---

# CloudWatch Log Group

The Lambda log group was created explicitly with Terraform.

Log Group:

/aws/lambda/patrik-cloudwatch-observability

Retention:

7 days

Creating the Log Group explicitly allowed Terraform to control:

- retention
- tags
- lifecycle

rather than relying only on automatic resource creation.

---

# Lambda Invocation Tests

The Lambda was invoked manually using AWS CLI.

Three scenarios were tested.

Success:

{"mode":"success"}

Warning:

{"mode":"warning"}

Error:

{"mode":"error"}

The error invocation produced:

FunctionError: Unhandled

and the function returned:

Simulated application error

This demonstrated an important distinction:

HTTP/API invocation success
does not necessarily mean
application execution success.

---

# CloudWatch Logs

CloudWatch Logs stored detailed execution information from the Lambda.

Examples included:

- execution mode
- application messages
- warnings
- errors
- stack traces
- request IDs
- execution duration
- billed duration
- memory usage

Logs answer questions such as:

- What happened?
- Which request failed?
- What was the exact error?
- What was the stack trace?
- When did it happen?

---

# Native Lambda Metrics

AWS Lambda automatically publishes metrics to CloudWatch.

Examples:

- Invocations
- Errors
- Duration
- Throttles
- ConcurrentExecutions

The native metric tested in this lab was:

Namespace:

AWS/Lambda

Metric:

Errors

Dimension:

FunctionName = patrik-cloudwatch-observability

Two controlled Lambda failures generated:

Errors = 2

This demonstrated the difference between logs and metrics.

Logs:

Detailed event information.

Metrics:

Numeric values aggregated over time.

---

# Metric Filter

A custom application warning was logged as text:

Simulated warning event

AWS does not automatically understand the business meaning of this message.

A CloudWatch Metric Filter was created to detect this log pattern.

Flow:

CloudWatch Logs
   |
   | finds:
   |
   | "Simulated warning event"
   v
Metric Filter
   |
   v
Custom Metric

Namespace:

PatrikCloudPlatform

Metric:

ApplicationWarnings

Value:

1

This transformed:

text

into:

numeric telemetry

Conceptually:

LOG
   |
   v
Metric Filter
   |
   v
METRIC

---

# Custom Metric

The custom metric was queried directly through the AWS CLI.

Example result:

ApplicationWarnings = 1

This confirmed that the Metric Filter successfully transformed the log event into a CloudWatch metric.

---

# CloudWatch Alarm for Application Warnings

A CloudWatch Alarm was created for the custom metric.

Alarm:

patrik-application-warning-alarm

Metric:

ApplicationWarnings

Condition:

ApplicationWarnings >= 1

Period:

60 seconds

Evaluation Periods:

1

Missing Data:

notBreaching

Conceptually:

ApplicationWarnings
       |
       | >= 1 ?
       v
     ALARM

The alarm successfully transitioned from:

OK

to:

ALARM

after a warning event was generated.

Later, with no new datapoints, it returned to:

OK

because:

treat_missing_data = notBreaching

---

# Native Lambda Error Alarm

A second CloudWatch Alarm was created using the native AWS Lambda Errors metric.

Alarm:

patrik-lambda-error-alarm

Metric:

AWS/Lambda Errors

Condition:

Errors >= 1

This demonstrated two different observability patterns.

Custom metric path:

Application
   |
   v
Log
   |
   v
Metric Filter
   |
   v
Custom Metric
   |
   v
Alarm

Native metric path:

Lambda
   |
   v
AWS/Lambda Errors
   |
   v
Alarm

This leads to an important rule:

If AWS already provides a useful native metric, use it.

Create custom metrics when the signal is specific to the application or business.

---

# CloudWatch Alarm States

CloudWatch Alarms can have states such as:

OK

ALARM

INSUFFICIENT_DATA

In this lab, both alarms were observed transitioning between:

OK

and:

ALARM

The threshold line in the CloudWatch Console visually represented when the metric crossed the configured condition.

Conceptually:

Metric Value
     |
     |        *
     |-------- threshold
     |
     +------------------- time

If:

metric >= threshold

then:

ALARM

Otherwise:

OK

---

# CloudWatch Dashboard

A CloudWatch Dashboard was created with four widgets:

Lambda Invocations

Lambda Errors

Lambda Duration

Application Warnings

Dashboard:

patrik-cloudwatch-observability

Visual layout:

+----------------------+----------------------+
| Lambda Invocations   | Lambda Errors        |
+----------------------+----------------------+
| Lambda Duration      | Application Warnings |
+----------------------+----------------------+

The dashboard showed both:

AWS native metrics

and:

custom application metrics

in the same place.

This made it easier to see application behavior visually.

---

# Dashboard Interpretation

Lambda Invocations

Shows how many times the function was called.

---

Lambda Errors

Shows how many Lambda invocations failed.

---

Lambda Duration

Shows how long the Lambda function took to execute.

This can help detect:

- slow execution
- cold starts
- external dependency latency
- performance degradation

---

Application Warnings

Shows warning events extracted from CloudWatch Logs through the Metric Filter.

This metric was created manually by the lab.

---

# CloudWatch Logs Insights

CloudWatch Logs Insights was used to query logs.

Basic query:

fields @timestamp, @message
| sort @timestamp desc
| limit 20

This returned:

- Lambda START events
- application logs
- warnings
- END events
- REPORT events

Logs Insights behaves conceptually like a query engine for logs.

---

# Filtering Warnings

Warnings were filtered with:

filter @message like /WARNING/

This returned only log lines containing warnings.

The query found:

4 warning records

from:

28 scanned log events

This demonstrated how Logs Insights can reduce large log volumes into relevant events.

---

# Aggregating Warnings

Warnings were aggregated by time period.

Concept:

filter WARNING
   |
   v
group by 1 hour
   |
   v
count

Example result:

2026-10-15 19:00
1 warning

2026-10-14 21:00
1 warning

2026-10-14 20:00
2 warnings

This transformed raw logs into an operational trend.

---

# Query Time Range

An important troubleshooting lesson occurred when a query returned no ERROR results.

The query itself was correct.

The problem was the time range.

The original query searched only the previous 24 hours.

The error logs were slightly older.

After expanding the query window to 48 hours, the expected results appeared.

Important lesson:

Correct query
+
existing data
does not guarantee results

because:

time range
is also part of the investigation.

---

# Error Aggregation

The error query returned:

4 ERROR log lines

while the native Lambda Errors metric showed:

2 failed invocations.

This happened because each failed Lambda invocation generated multiple ERROR log lines.

Example:

Invocation 1

ERROR Simulated application failure

ERROR Exception: Simulated application error

Invocation 2

ERROR Simulated application failure

ERROR Exception: Simulated application error

Therefore:

Logs Insights ERROR count = 4

Lambda Errors metric = 2

This demonstrates an important distinction.

Native Lambda Errors:

Counts failed invocations.

Logs Insights ERROR filter:

Counts log records containing the word ERROR.

Metrics and logs answer different questions.

---

# Observability Troubleshooting Model

A useful mental model from this lab is:

Dashboard
   |
   v
Something looks wrong
   |
   v
Metric
   |
   v
How much / how often?
   |
   v
Alarm
   |
   v
Did it cross a threshold?
   |
   v
Logs
   |
   v
What happened?
   |
   v
Logs Insights
   |
   v
Why did it happen?

A practical summary:

Dashboard
=
detect visually

Metric
=
quantify

Alarm
=
notify / identify threshold violation

Logs
=
explain

Logs Insights
=
investigate

---

# CloudWatch as an Observability Platform

Before this lab, observability may commonly be associated with tools such as:

Prometheus

Grafana

Datadog

However, CloudWatch is also an observability platform.

CloudWatch provides:

Metrics

Logs

Alarms

Dashboards

Logs Insights

AWS service integrations

CloudWatch can therefore be considered:

AWS-native observability

---

# Relationship with Other Observability Tools

A useful conceptual comparison:

CloudWatch Metrics

similar role to:

Prometheus metrics

---

CloudWatch Dashboard

similar visualization role to:

Grafana dashboards

---

CloudWatch Logs

similar logging role to:

Loki or another logging backend

---

CloudWatch Alarms

similar alerting role to:

Prometheus Alertmanager
or
Grafana Alerting

These are not exact technical equivalents, but the comparison helps understand the observability model.

---

# Future Observability Roadmap

The next observability topics will include:

Prometheus

Grafana

Loki

Tempo / Jaeger

OpenTelemetry

Datadog

CloudWatch Application Signals

AWS X-Ray

The goal is to understand both:

AWS-native observability

and:

cloud-native observability

---

# Visual Mental Model

The complete Lab 08 architecture can be represented as:

                    AWS Lambda
                         |
          +--------------+--------------+
          |                             |
          v                             v
   CloudWatch Logs                AWS/Lambda Metrics
          |                             |
          |                             +--> Errors
          |
          +--> Logs Insights
          |
          +--> Metric Filter
                  |
                  v
         ApplicationWarnings
                  |
                  v
                Alarm

AWS/Lambda Errors
       |
       v
     Alarm

All relevant metrics
       |
       v
CloudWatch Dashboard

---

# Key Lessons

Main concepts learned:

- Logs and metrics are different signals
- CloudWatch provides AWS-native observability
- Lambda automatically publishes native metrics
- Logs contain detailed event information
- Metrics provide numeric time-series information
- Metric Filters can transform logs into metrics
- Custom metrics represent application-specific signals
- Alarms evaluate metrics against thresholds
- Missing data behavior affects alarm state
- Dashboards visualize multiple metrics together
- Logs Insights enables log filtering and aggregation
- Query time ranges matter
- Log error counts are not necessarily equal to failed application executions
- Native metrics should be preferred when they already represent the desired signal

---

# Interview Summary

A concise explanation:

"I built an AWS observability lab using Lambda and CloudWatch.

The Lambda generated success, warning and error scenarios. Application logs were sent to CloudWatch Logs, while Lambda automatically published native metrics such as Invocations, Errors and Duration.

For application-specific warnings, I created a CloudWatch Metric Filter that transformed warning log events into a custom metric called ApplicationWarnings.

I created CloudWatch Alarms for both the custom warning metric and the native Lambda Errors metric.

I also built a CloudWatch Dashboard combining native and custom metrics, and used CloudWatch Logs Insights to filter and aggregate warning and error events.

The lab helped demonstrate the difference between logs, metrics, alarms and dashboards, and how they work together during troubleshooting."

---

# Lab Status

Completed.

Validated components:

CloudWatch Logs
✅

Native AWS Metrics
✅

Custom Metric
✅

Metric Filter
✅

CloudWatch Alarms
✅

CloudWatch Dashboard
✅

Logs Insights
✅

Controlled Warning Test
✅

Controlled Error Test
✅

Alarm State Transition
✅