-- Setup Instructions for Tavily Web Search Custom Tool
-- Execute these commands in your Snowflake environment

-- Adapt you role to Snowflake Intelligence Users inf needed
SET TAVILY_API_KEY = '<tavily API key>';
SET SNOWFLAKE_INTELLIGENCE_ROLE = 'PUBLIC';
SET TARGET_DATABASE = 'SNOWFLAKE_INTELLIGENCE';
SET TARGET_SCHEMA = 'TOOLS';


-- 1. Create a database for custom tools (if not exists)
CREATE DATABASE IF NOT EXISTS IDENTIFIER($TARGET_DATABASE);
GRANT USAGE ON DATABASE IDENTIFIER($TARGET_DATABASE) TO ROLE IDENTIFIER($SNOWFLAKE_INTELLIGENCE_ROLE);
USE DATABASE IDENTIFIER($TARGET_DATABASE);

-- 2. Create schema for custom procedures
CREATE SCHEMA IF NOT EXISTS IDENTIFIER($TARGET_SCHEMA);
GRANT USAGE ON SCHEMA IDENTIFIER($TARGET_SCHEMA) TO ROLE IDENTIFIER($SNOWFLAKE_INTELLIGENCE_ROLE);
USE SCHEMA IDENTIFIER($TARGET_SCHEMA);


-- 3. Create Snowflake Secret for Tavily API Key (RECOMMENDED METHOD)

-- Create the secret (requires appropriate privileges)
CREATE SECRET IF NOT EXISTS TAVILY_API_KEY
TYPE = GENERIC_STRING
SECRET_STRING = $TAVILY_API_KEY
COMMENT = 'API key for Tavily web search service';

-- Grant access to the secret to roles that will use the procedure
GRANT USAGE ON SECRET TAVILY_API_KEY TO ROLE IDENTIFIER($SNOWFLAKE_INTELLIGENCE_ROLE);

-- Alternative: If you need to update an existing secret
-- ALTER SECRET TAVILY_API_KEY SET SECRET_STRING = 'your_new_tavily_api_key_here';

-- 4. Grant PyPI repository access (required for packages)
-- Account administrator must grant this role
GRANT DATABASE ROLE SNOWFLAKE.PYPI_REPOSITORY_USER TO ROLE IDENTIFIER($SNOWFLAKE_INTELLIGENCE_ROLE);

-- 5. Create External Access Integration for Tavily API
CREATE OR REPLACE NETWORK RULE tavily_network_rule
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = ('api.tavily.com:443');

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION TAVILY_ACCESS_INTEGRATION
  ALLOWED_NETWORK_RULES = (tavily_network_rule)
  ALLOWED_AUTHENTICATION_SECRETS = (TAVILY_API_KEY)
  ENABLED = true
  COMMENT = 'External access integration for Tavily web search API';

-- Grant usage on the integration
GRANT USAGE ON INTEGRATION TAVILY_ACCESS_INTEGRATION TO ROLE IDENTIFIER($SNOWFLAKE_INTELLIGENCE_ROLE);

-- 6. Create the stored procedure
-- Note: The procedure includes a SECRETS clause that maps 'tavily_cred' to TAVILY_API_KEY
CREATE OR REPLACE PROCEDURE TAVILY_WEB_SEARCH(
    SEARCH_QUERY STRING,
    MAX_RESULTS NUMBER DEFAULT 5,
    SEARCH_DEPTH STRING DEFAULT 'basic',
    INCLUDE_DOMAINS STRING DEFAULT '',
    EXCLUDE_DOMAINS STRING DEFAULT ''
)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
ARTIFACT_REPOSITORY = snowflake.snowpark.pypi_shared_repository
PACKAGES = ('snowflake-snowpark-python','tavily-python','snowflake-telemetry-python','opentelemetry-api')
EXTERNAL_ACCESS_INTEGRATIONS = (TAVILY_ACCESS_INTEGRATION)
SECRETS = ('tavily_cred' = TAVILY_API_KEY)
HANDLER = 'perform_web_search'
COMMENT = 'Advanced web search function for real-time information retrieval. Performs intelligent web searches using the Tavily API to find current, relevant information from across the internet. Ideal for answering questions that require up-to-date information, fact-checking, research, and gathering current data not available in training datasets. Returns structured JSON results with titles, URLs, content snippets, and relevance scores. Automatically filters and optimizes results for AI consumption while respecting domain preferences and size constraints.'
AS
$$
import json
from tavily import TavilyClient
import _snowflake
from snowflake import telemetry
from opentelemetry import trace

def perform_web_search(search_query, max_results=5, search_depth='basic', include_domains='', exclude_domains=''):
    """
    Performs web search using Tavily Client and returns formatted results.
    
    Args:
        search_query (str): The search query string
        max_results (int): Maximum number of results to return (default: 5)
        search_depth (str): The depth of the search (default: basic)
        include_domains (str): Comma-separated list of domains to include
        exclude_domains (str): Comma-separated list of domains to exclude
    
    Returns:
        str: JSON string containing search results, limited to 16KB for Snowflake Intelligence
    """
    
    # Set essential span attributes for tracking
    telemetry.set_span_attribute("tavily.search.query", search_query[:100])  # Truncate for safety
    telemetry.set_span_attribute("tavily.search.max_results", max_results)
    telemetry.set_span_attribute("tavily.search.search_depth", search_depth)
    telemetry.set_span_attribute("tavily.procedure.status", "started")
    
    try:
        # Initialize Tavily Client using Snowflake Secret
        try:
            api_key = _snowflake.get_generic_secret_string('tavily_cred')
        except Exception as secret_error:
            telemetry.set_span_attribute("tavily.procedure.status", "error_secret_retrieval")
            return json.dumps({
                "error": f"Failed to retrieve Tavily API key from Snowflake Secret: {str(secret_error)}",
                "status": "error",
                "help": "Ensure the TAVILY_API_KEY secret exists and is mapped correctly in the SECRETS clause"
            })
        
        if not api_key:
            telemetry.set_span_attribute("tavily.procedure.status", "error_empty_key")
            return json.dumps({
                "error": "Tavily API key not found in Snowflake Secret",
                "status": "error",
                "help": "Create the secret using: CREATE SECRET TAVILY_API_KEY TYPE = GENERIC_STRING SECRET_STRING = 'your_api_key'"
            })
        
        # Initialize Tavily client
        tavily_client = TavilyClient(api_key=api_key)
        
        # Prepare search parameters
        search_params = {
            "query": search_query,
            "auto_parameters": True,
            "include_answer": True,
            "include_raw_content": False,
            "search_depth": search_depth,
            "max_results": min(max_results, 10),  # Limit to prevent oversized responses
        }
        
        # Add domain filters if provided
        if include_domains and include_domains.strip():
            search_params["include_domains"] = [domain.strip() for domain in include_domains.split(',') if domain.strip()]
        
        if exclude_domains and exclude_domains.strip():
            search_params["exclude_domains"] = [domain.strip() for domain in exclude_domains.split(',') if domain.strip()]
        
        # Perform the search within a custom span for precise timing
        tracer = trace.get_tracer("tavily.search.tracer")
        
        with tracer.start_as_current_span("tavily_api_search") as search_span:
            try:
                # Essential custom span attributes
                search_span.set_attribute("search.query", search_query[:100])  # Truncate for safety
                search_span.set_attribute("search.max_results", search_params["max_results"])
                search_span.set_attribute("search.depth", search_depth)
                
                # Execute the actual search
                response = tavily_client.search(**search_params)
                
                # Set result attributes on custom span
                search_span.set_attribute("search.results_count", len(response.get("results", [])))
                search_span.set_attribute("search.success", True)
                
            except Exception as search_error:
                # Handle errors within the custom span
                search_span.set_attribute("search.success", False)
                search_span.set_attribute("search.error_type", type(search_error).__name__)
                # Re-raise the exception to be handled by the outer try-catch
                raise
        
        # Also add to main span for backward compatibility
        telemetry.set_span_attribute("tavily.search.results_count", len(response.get("results", [])))
        
        max_size = 16384  # 16KB (16 * 1024)
        response_json = json.dumps(response, ensure_ascii=False)
        original_size = len(response_json)
        
        # Set response size attribute
        telemetry.set_span_attribute("tavily.response.original_size", original_size)
        
        if len(response_json) > max_size:
            # Format response for Snowflake Intelligence (keeping within 16KB limit)
            formatted_results = {
                "query": search_query,
                "results_count": len(response.get("results", [])),
                "results": []
            }
            
            # Process results and ensure we stay within size limits
            current_size = 0
            included_results = 0
            
            for result in response.get("results", []):
                # Create a simplified result object
                simplified_result = {
                    "title": result.get("title", "")[:200],  # Limit title length
                    "url": result.get("url", ""),
                    "content": result.get("content", "")[:1000],  # Limit content length
                    "score": result.get("score", 0)
                }
                
                # Estimate size and check if we can add this result
                result_json = json.dumps(simplified_result)
                if current_size + len(result_json) < max_size:
                    formatted_results["results"].append(simplified_result)
                    current_size += len(result_json)
                    included_results += 1
                else:
                    break
            
            # Add metadata
            formatted_results["status"] = "success"
            formatted_results["timestamp"] = response.get("query_time", "")
            response_json = json.dumps(formatted_results, ensure_ascii=False)
            
            # Set truncation attributes
            telemetry.set_span_attribute("tavily.response.truncated", True)
            telemetry.set_span_attribute("tavily.response.final_results_count", included_results)
        else:
            telemetry.set_span_attribute("tavily.response.truncated", False)

        # Final success tracking
        telemetry.set_span_attribute("tavily.procedure.status", "success")
        telemetry.set_span_attribute("tavily.response.final_size", len(response_json))

        return response_json
        
    except Exception as e:
        # Error tracking
        telemetry.set_span_attribute("tavily.procedure.status", "error")
        telemetry.set_span_attribute("tavily.error.type", type(e).__name__)
        
        # Return error information in a structured format
        error_response = {
            "error": str(e),
            "query": search_query,
            "status": "error"
        }
        return json.dumps(error_response)
$$;

-- Grant usage on the specific procedure
GRANT USAGE ON PROCEDURE SNOWFLAKE_INTELLIGENCE.TOOLS.TAVILY_WEB_SEARCH(STRING, NUMBER, STRING, STRING, STRING) TO ROLE IDENTIFIER($SNOWFLAKE_INTELLIGENCE_ROLE);

-- 9. Test the procedure
USE ROLE IDENTIFIER($SNOWFLAKE_INTELLIGENCE_ROLE);
CALL SNOWFLAKE_INTELLIGENCE.TOOLS.TAVILY_WEB_SEARCH('Latest Snowflake Feature Releases')
->> 
WITH rs AS (
    SELECT parse_json($1) AS J FROM $1
)
SELECT
    rs.j:"query"::string AS query,
    r.value:"title"::string AS title,
    r.value:"url"::string AS url,
    r.value:"content"::string AS content,
    r.value:"score"::float AS score
FROM rs, LATERAL FLATTEN(input => rs.j:"results") r;