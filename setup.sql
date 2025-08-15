-- Setup Instructions for Tavily Web Search Custom Tool for Cortex Agent
-- Execute these commands in your Snowflake environment

-- Adapt you role to Snowflake Intelligence Users inf needed
SET TAVILY_API_KEY = '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';
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
GRANT READ ON SECRET TAVILY_API_KEY TO ROLE IDENTIFIER($SNOWFLAKE_INTELLIGENCE_ROLE);

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

-- 6. Create the stored procedure (copy from tavily_web_search_procedure.sql)
-- Note: The procedure includes a SECRETS clause that maps 'tavily_cred' to TAVILY_API_KEY

-- Grant usage on the specific procedure
GRANT USAGE ON PROCEDURE SNOWFLAKE_INTELLIGENCE.TOOLS.TAVILY_WEB_SEARCH(STRING, NUMBER, STRING, STRING) TO ROLE PUBLIC;

-- Grant read access to the secret (if not already granted in step 3)
GRANT READ ON SECRET TAVILY_API_KEY TO ROLE IDENTIFIER($SNOWFLAKE_INTELLIGENCE_ROLE);

-- 8. Test the procedure
CALL SNOWFLAKE_INTELLIGENCE.TOOLS.TAVILY_WEB_SEARCH('Latest Snowflake Feature Releases', 5, '', '')
->> 
WITH rs AS (
    SELECT parse_json(TAVILY_WEB_SEARCH) AS $1
)
SELECT
    rs.j:"query"::string AS query,
    r.value:"title"::string AS title,
    r.value:"url"::string AS url,
    r.value:"content"::string AS content,
    r.value:"score"::float AS score
FROM rs, LATERAL FLATTEN(input => rs.j:"results") r;

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
PACKAGES = ('snowflake-snowpark-python','tavily-python')
EXTERNAL_ACCESS_INTEGRATIONS = (TAVILY_ACCESS_INTEGRATION)
SECRETS = ('tavily_cred' = TAVILY_API_KEY)
HANDLER = 'perform_web_search'
COMMENT = 'TAVILY_WEB_SEARCH: Advanced web search function for real-time information retrieval. Performs intelligent web searches using the Tavily API to find current, relevant information from across the internet. Ideal for answering questions that require up-to-date information, fact-checking, research, and gathering current data not available in training datasets. Returns structured JSON results with titles, URLs, content snippets, and relevance scores. Automatically filters and optimizes results for AI consumption while respecting domain preferences and size constraints.'
AS
$$
import json
from tavily import TavilyClient
import _snowflake

def perform_web_search(search_query, max_results=5, include_domains='', search_depth='basic', exclude_domains=''):
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
    
    try:
        # Initialize Tavily Client using Snowflake Secret
        # Retrieve the API key from Snowflake Secret using native Python API
        try:
            api_key = _snowflake.get_generic_secret_string('tavily_cred')
        except Exception as secret_error:
            return json.dumps({
                "error": f"Failed to retrieve Tavily API key from Snowflake Secret: {str(secret_error)}",
                "status": "error",
                "help": "Ensure the TAVILY_API_KEY secret exists and is mapped correctly in the SECRETS clause"
            })
        
        if not api_key:
            return json.dumps({
                "error": "Tavily API key not found in Snowflake Secret",
                "status": "error",
                "help": "Create the secret using: CREATE SECRET TAVILY_API_KEY TYPE = GENERIC_STRING SECRET_STRING = 'your_api_key'"
            })
        
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
        
        # Perform the search
        response = tavily_client.search(**search_params)
        
        max_size = 16384  # 16KB (16 * 1024)
        response_json = json.dumps(response, ensure_ascii=False)
        if len(response_json) > max_size:
            # Keep original response structure but trim content to fit within 16KB limit
            formatted_results = response.copy()  # Start with original response
            
            # Process results and trim content while keeping structure
            trimmed_results = []
            current_size = len(json.dumps({k: v for k, v in formatted_results.items() if k != "results"}))
            
            for result in response.get("results", []):
                # Create trimmed result preserving all original fields
                trimmed_result = result.copy()
                
                # Trim only the content field that tends to be large
                if "content" in trimmed_result:
                    trimmed_result["content"] = trimmed_result["content"][:1000]
                
                # Check if we can add this result
                result_json = json.dumps(trimmed_result)
                if current_size + len(result_json) < max_size - 100:  # Leave buffer
                    trimmed_results.append(trimmed_result)
                    current_size += len(result_json)
                else:
                    break
            
            formatted_results["results"] = trimmed_results
            response_json = json.dumps(formatted_results, ensure_ascii=False)

        return response_json
        
    except Exception as e:
        # Return error information in a structured format
        error_response = {
            "error": str(e),
            "query": search_query,
            "status": "error"
        }
        return json.dumps(error_response)
$$;
