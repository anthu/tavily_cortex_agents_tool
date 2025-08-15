# TAVILY_WEB_SEARCH Function Documentation for Orchestration Agents

## Function Overview
**TAVILY_WEB_SEARCH** is an advanced web search function that provides real-time information retrieval from the internet. Use this function when you need current, up-to-date information that may not be available in your training data.

## Function Signature
```sql
TAVILY_WEB_SEARCH(
    SEARCH_QUERY STRING,
    MAX_RESULTS NUMBER DEFAULT 5,
    SEARCH_DEPTH STRING DEFAULT 'basic',
    INCLUDE_DOMAINS STRING DEFAULT '',
    EXCLUDE_DOMAINS STRING DEFAULT ''
) RETURNS STRING
```

## Parameters

### SEARCH_QUERY (Required)
- **Type**: STRING
- **Description**: The search terms or question to search for on the web
- **Best Practices**: 
  - Use clear, specific queries
  - Include relevant context
  - Avoid overly broad terms
- **Examples**: 
  - `"latest Tesla stock price"`
  - `"COVID-19 vaccination rates 2024"`
  - `"current weather in New York"`
  - `"recent AI breakthroughs"`

### MAX_RESULTS (Optional)
- **Type**: NUMBER
- **Default**: 5
- **Range**: 1-10
- **Description**: Maximum number of search results to return
- **Guidelines**:
  - Fewer results = faster response, lower token usage
  - More results = broader information coverage
  - Recommended: 3-5 for focused queries, 5-10 for research

### SEARCH_DEPTH (Optional)
- **Type**: STRING
- **Default**: 'basic'
- **Options**: 'basic', 'advanced'
- **Description**: Controls the depth and comprehensiveness of the search
- **Guidelines**:
  - 'basic': Faster searches, good for quick information retrieval
  - 'advanced': More thorough searches, better for comprehensive research
  - Advanced searches may take longer but provide more detailed results

### INCLUDE_DOMAINS (Optional)
- **Type**: STRING
- **Default**: '' (empty)
- **Format**: Comma-separated domain list
- **Description**: Specific domains to search within for trusted sources
- **Examples**:
  - News: `"reuters.com,bbc.com"`
  - Technical: `"github.com,stackoverflow.com"`
  - Financial: `"sec.gov,investor.gov"`
  - Weather: `"weather.com,accuweather.com"`

### EXCLUDE_DOMAINS (Optional)
- **Type**: STRING
- **Default**: '' (empty)
- **Format**: Comma-separated domain list
- **Description**: Domains to exclude from search results
- **Examples**:
  - `"wikipedia.org"` to exclude Wikipedia
  - `"reddit.com,quora.com"` to exclude social platforms

## Return Value
Returns a JSON string with the following structure:
```json
{
  "query": "original search query",
  "answer": "Direct answer to the search query based on the search results",
  "images": [],
  "results": [
    {
      "title": "Result title (preserved in full)",
      "url": "https://example.com/article",
      "content": "Relevant content snippet (trimmed to 1000 chars)",
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

## Usage Examples

### 1. Current Events/News
```sql
CALL TAVILY_WEB_SEARCH(
    'latest developments artificial intelligence 2024', 
    5, 
    'basic',
    'reuters.com,techcrunch.com', 
    ''
);
```

### 2. Financial Information
```sql
CALL TAVILY_WEB_SEARCH(
    'Tesla stock price today', 
    3, 
    'basic',
    'yahoo.com,bloomberg.com', 
    ''
);
```

### 3. Weather Information
```sql
CALL TAVILY_WEB_SEARCH(
    'current weather forecast New York City', 
    2, 
    'basic',
    'weather.com,accuweather.com', 
    ''
);
```

### 4. Technical Research
```sql
CALL TAVILY_WEB_SEARCH(
    'Python asyncio best practices 2024', 
    5, 
    'advanced',
    'stackoverflow.com,realpython.com', 
    'w3schools.com'
);
```

### 5. General Research
```sql
CALL TAVILY_WEB_SEARCH(
    'climate change impact agriculture', 
    7, 
    'advanced',
    '', 
    'wikipedia.org'
);
```

## When to Use This Function

### ✅ Use TAVILY_WEB_SEARCH when:
- User asks about current events, recent news, or real-time information
- Need to verify facts or get updated information
- Research topics requiring current data (stock prices, weather, etc.)
- Supplement knowledge with recent developments in any field
- Fact-checking or validation of claims
- Getting diverse perspectives from multiple sources
- Information may be newer than your training data cutoff

### ❌ Avoid using when:
- Information is likely static (historical facts, basic definitions)
- User asks about general knowledge available in training data
- Question doesn't require real-time or current information
- Making multiple similar searches (consolidate queries instead)

## Error Handling
The function returns structured error information in JSON format:
```json
{
  "error": "Error description",
  "query": "original search query",
  "status": "error"
}
```

## Performance Considerations
- Results are automatically limited to stay within Snowflake's 16KB return limit
- Content snippets are truncated to 500 characters per result
- Titles are limited to 200 characters
- Function includes built-in caching and optimization
- External API calls may add 1-3 seconds to response time

## Security & Compliance
- Uses Snowflake's secure secret management for API credentials
- External access is controlled through Snowflake's access integration
- All network communication is encrypted (HTTPS)
- No sensitive data is stored or logged by the function
