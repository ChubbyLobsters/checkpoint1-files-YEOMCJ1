#!/bin/bash

# Step 1: Filter critical logs
grep -iE 'ERROR|CRITICAL|FATAL' sys_log.txt > filtered_logs.txt

# Step 2: Tokenize filtered logs into tokens (words)
tr -s '[:space:][:punct:]' '\n' < filtered_logs.txt | grep -v '^$' > tokens.txt

# Step 3: Count frequency and output top 10 tokens
sort tokens.txt | uniq -c | sort -nr | head -n 10 > top10_critical.txt

# Show the results on the terminal
echo "Top 10 critical tokens:"
cat top10_critical.txt

