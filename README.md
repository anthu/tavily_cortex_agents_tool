# Tavily Web Search Custom Tool for Snowflake Intelligence

This repository contains a custom tool implementation for Snowflake Intelligence that enables web search capabilities using the Tavily Client. The tool is implemented as a Snowflake stored procedure that can be integrated into Snowflake Intelligence agents.

## Overview

The Tavily Web Search custom tool allows Snowflake Intelligence agents to perform real-time web searches and incorporate external information into their responses. This extends the agent's knowledge beyond your Snowflake data to include current web information.

## Features

- Real-time web search using Tavily's advanced search API
- SECRETS clause integration for secure API key mapping
- Native Python secret access using `_snowflake` module for optimal security
- Configurable result limits to optimize performance
- Domain filtering (include/exclude specific domains)
- Response size optimization to comply with Snowflake Intelligence 16KB limit
- Error handling and structured response formatting
- Compatible with Snowflake Intelligence custom tool requirements

## Prerequisites

1. **Tavily API Key**: Sign up at [Tavily](https://tavily.com) and obtain an API key
2. **Snowflake Account**: Access to a Snowflake account with privileges to create stored procedures
3. **Snowflake Intelligence**: Access to Snowflake Intelligence features
4. **Python Runtime**: Snowflake Python runtime version 3.9 or higher

## Installation

### Step 1: Copy Setup Script to Workspaces in Snowflake

1. Download or copy the contents of [`setup.sql`](setup.sql)
2. Open Snowsight and navigate to **Worksheets**
3. Create a new worksheet and paste the entire setup script
4. Proceed to Step 2 to review and modify the variables before execution

### Step 2: Review Script Variables
Review and update the following variables at the top of setup.sql:
- `TAVILY_API_KEY`: Your Tavily API key from [tavily.com](https://tavily.com). Replace the placeholder value with your actual API key.
- `SNOWFLAKE_INTELLIGENCE_ROLE`: The role that will have access to the custom tool. Default is `'PUBLIC'`, but you should change this to the specific role used by your Snowflake Intelligence agents.
- `TARGET_DATABASE`: The database where the procedure will be created. Default is `'SNOWFLAKE_INTELLIGENCE'`.
- `TARGET_SCHEMA`: The schema within the database where the procedure will be created. Default is `'TOOLS'`.


### Step 3: Add to Snowflake Intelligence Agent

1. Sign in to Snowsight
2. Navigate to **AI & ML** > **Agents**
3. Select the agent you want to enhance
4. Click **Edit**
5. Go to the **Tools** section
6. Find **Custom tools** and click **+ Add**
7. Configure the custom tool:
   - **Name**: `Tavily Web Search`
   - **Resource Type**: `Procedure`
   - **Custom Tool Identifier**: Select `TAVILY_WEB_SEARCH`
   - **Warehouse**: Select an appropriate warehouse
   - **Query Timeout (Seconds)**: 180
8. Parameter Configurations and Instructions see next secion

### Step 4: Instructions and Descriptions:

1. **Tool Description**
```
TAVILY_WEB_SEARCH is an advanced web search function that provides real-time information retrieval from the internet. Use this function to search for current events, breaking news, real-time data, and up-to-date information that may not be available in your training data.

The function performs intelligent web searches and returns structured results optimized for AI processing. It is ideal for:
- Retrieving current events and recent news
- Verifying facts and getting updated information
- Researching topics requiring real-time data (e.g. stock prices, weather)
- Supplementing knowledge with latest developments
- Fact-checking claims
- Getting diverse perspectives from multiple sources

Do not use this function when:
- Information needed is static (historical facts, basic definitions)
- Query is about general knowledge available in training data
- Real-time/current information is not required
- Making multiple similar searches (consolidate queries instead)
```

2. **SEARCH_QUERY (STRING, REQUIRED):**
```
The search terms or question to search for on the web. Should be a clear, specific query
that describes the information you need. Examples: "latest Tesla stock price", 
"COVID-19 vaccination rates 2024", "current weather in New York", "recent AI breakthroughs".
Best practices: Use specific keywords, include relevant context, avoid overly broad terms.
```

3. **MAX_RESULTS (NUMBER, OPTIONAL, DEFAULT: 5):**
```
Maximum number of search results to return (1-10). Fewer results = faster response and
lower token usage. More results = broader information coverage. Recommended: 3-5 for 
focused queries, 5-10 for comprehensive research. The function automatically limits to 
prevent oversized responses that exceed Snowflake's return size limits.
```

4. **SEARCH_DEPTH (STRING, OPTIONAL, DEFAULT: 'basic'):**
```
Controls the depth and comprehensiveness of the search. Options are 'basic' and 'advanced'.
'basic' provides faster searches suitable for quick information retrieval, while 'advanced'
performs more thorough searches better suited for comprehensive research. Advanced searches
may take longer but provide more detailed and extensive results.
```

5. **INCLUDE_DOMAINS (STRING, OPTIONAL, DEFAULT: ''):**
```
Comma-separated list of specific domains to search within. Use when you want results
only from trusted or specific sources. Examples: "reuters.com,bbc.com" for news,
"github.com,stackoverflow.com" for technical content, "sec.gov,investor.gov" for 
financial data. Leave empty for general web search across all domains.
```

6. **EXCLUDE_DOMAINS (STRING, OPTIONAL, DEFAULT: ''):**
```
Comma-separated list of domains to exclude from search results. Use to filter out
unreliable sources or irrelevant content types. Examples: "wikipedia.org" to exclude
Wikipedia, "reddit.com,quora.com" to exclude social platforms. Leave empty to allow
all domains except those filtered by Tavily's built-in quality controls.
```

## Usage Examples

### Basic Web Search
```sql
CALL TAVILY_WEB_SEARCH('latest AI developments 2025');
```

### Search with Domain Filtering
```sql
-- Include only specific domains
CALL TAVILY_WEB_SEARCH(
    SEARCH_QUERY => 'machine learning tutorials',
    MAX_RESULTS => 3,
    INCLUDE_DOMAINS => 'medium.com,towardsdatascience.com'
);

-- Exclude specific domains
CALL TAVILY_WEB_SEARCH(
    SEARCH_QUERY => 'Python programming tips',
    EXCLUDE_DOMAINS => 'stackoverflow.com,reddit.com'
);
```

### Advanced Search for Comprehensive Research
```sql
-- Using advanced search depth for detailed research
CALL TAVILY_WEB_SEARCH(
    SEARCH_QUERY => 'climate change renewable energy policies 2024',
    MAX_RESULTS => 7,
    SEARCH_DEPTH => 'advanced'
);
```

### Using in Snowflake Intelligence

Once configured, users can interact with the agent using natural language:

- "Search for the latest news about artificial intelligence"
- "Find information about Snowflake's recent product announcements"
- "Look up current stock market trends"

## Response Format

The procedure returns a JSON string with the following structure:

```json
{
  "query": "search query",
  "answer": "Direct answer to the search query based on the search results",
  "images": [],
  "results": [
    {
      "title": "Article Title",
      "url": "https://example.com/article",
      "content": "Brief excerpt from the article...",
      "score": 0.95,
      "raw_content": null,
      "favicon": "https://example.com/favicon.png"
    }
  ],
  "auto_parameters": {
    "topic": "general",
    "search_depth": "basic"
  },
  "response_time": "1.67"
}
```

### Error Response Format

```json
{
  "error": "Error description",
  "query": "search query",
  "status": "error"
}
```

## Troubleshooting

### Common Issues

1. **"Tavily API key not found" Error**
   - Ensure the `TAVILY_API_KEY` secret exists and is properly configured
   - Verify you have READ privileges on the secret
   - Check that the API key value in the secret is valid and active

2. **"Procedure does not exist" Error**
   - Check that the procedure was created successfully
   - Verify you have the necessary privileges to execute the procedure

3. **Empty Results**
   - Verify your Tavily API key has remaining credits
   - Check if domain filters are too restrictive
   - Ensure the search query is not too specific
