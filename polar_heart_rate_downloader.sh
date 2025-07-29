#!/bin/bash

# Polar Heart Rate Data Downloader
# Downloads continuous heart rate data for the last 30 days

# Configuration - Read from environment variables (required)
CLIENT_ID="${CLIENT_ID}"
CLIENT_SECRET="${CLIENT_SECRET}"
MEMBER_ID="${MEMBER_ID}"
AUTH_CODE="${AUTH_CODE:-}"  # Optional - can be provided as parameter instead
OUTPUT_DIR="docs/continuous-heart-rate"
LOG_FILE="polar_download.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to show help
show_help() {
    cat << EOF
Polar Heart Rate Data Downloader

USAGE:
    $0 --chr [authorization_code]     # Code from parameter or AUTH_CODE env var
    $0 --ru [authorization_code] <user_id>  # Code from parameter or AUTH_CODE env var
    $0 --gui [authorization_code]     # Code from parameter or AUTH_CODE env var  
    $0 --gac
    $0 --help

DESCRIPTION:
    Downloads continuous heart rate data from Polar API for the last 30 days.
    Stores each day's data as a JSON file in the '$OUTPUT_DIR' directory.
    Authorization codes can be provided as parameters or via AUTH_CODE environment variable.

OPTIONS:
    --chr [code]         Download heart rate data (uses AUTH_CODE env var if no code provided)
    --ru [code] <id>     Register user (uses AUTH_CODE env var if no code provided)
    --gui [code]         Get user information (uses AUTH_CODE env var if no code provided)
    --gac                Open OAuth2 authorization URL in browser to get authorization code
    --help               Show this help message

EXAMPLES:
    # Using command line parameters:
    $0 --gac                                             # Get authorization code
    $0 --ru f6c3c71522e2fc8948af16b01e5edd9e 201787     # Register user (required first)
    $0 --gui f6c3c71522e2fc8948af16b01e5edd9e           # Get user info (after registration)
    $0 --chr f6c3c71522e2fc8948af16b01e5edd9e           # Download data
    
    # Using environment variable (set AUTH_CODE in polar_env.sh):
    $0 --ru 201787       # Register user using AUTH_CODE env var
    $0 --gui             # Get user info using AUTH_CODE env var
    $0 --chr             # Download data using AUTH_CODE env var

NOTES:
    - You need to obtain the authorization code first by visiting:
      https://flow.polar.com/oauth2/authorization?response_type=code&client_id=[YOUR_CLIENT_ID]
    - The script downloads data for the last 30 days (Polar API limitation)
    - The script will create a '$OUTPUT_DIR' directory if it doesn't exist
    - Each day's data will be saved as YYYY-MM-DD.json in the docs folder
    - A log file '$LOG_FILE' will track the download progress
    
ENVIRONMENT VARIABLES (REQUIRED):
    - CLIENT_ID: OAuth2 client ID (must be set)
    - CLIENT_SECRET: OAuth2 client secret (must be set)  
    - MEMBER_ID: Polar member ID (must be set)
    - AUTH_CODE: OAuth2 authorization code (optional - can be passed as parameter instead)
    - Use 'source polar_env.sh' to load these variables

EOF
}

# Function to open OAuth2 authorization URL
get_authorization_token() {
    # Check if CLIENT_ID is set
    if [ -z "$CLIENT_ID" ]; then
        print_status "$RED" "❌ Error: CLIENT_ID environment variable is not set!"
        print_status "$RED" "💡 Please run: source polar_env.sh"
        log_message "ERROR" "CLIENT_ID environment variable required for authorization URL"
        exit 1
    fi
    
    local auth_url="https://flow.polar.com/oauth2/authorization?response_type=code&client_id=${CLIENT_ID}"
    
    print_status "$BLUE" "🌐 Opening OAuth2 authorization URL in browser..."
    print_status "$GREEN" "📋 URL: $auth_url"
    log_message "INFO" "Opening OAuth2 authorization URL with CLIENT_ID: ${CLIENT_ID}"
    
    # Try to open the URL in the default browser
    if command -v open > /dev/null 2>&1; then
        # macOS
        open "$auth_url"
        print_status "$GREEN" "✅ URL opened in browser"
    elif command -v xdg-open > /dev/null 2>&1; then
        # Linux
        xdg-open "$auth_url"
        print_status "$GREEN" "✅ URL opened in browser"
    elif command -v start > /dev/null 2>&1; then
        # Windows
        start "$auth_url"
        print_status "$GREEN" "✅ URL opened in browser"
    else
        print_status "$YELLOW" "⚠️  Could not automatically open browser"
        print_status "$BLUE" "💡 Please manually open this URL in your browser:"
    fi
    
    echo ""
    print_status "$BLUE" "📋 Next steps:"
    echo "   1. Authorize the application in your browser"
    echo "   2. Copy the authorization code from the callback URL"
    echo "   3. Run: $0 --chr <authorization_code>"
    
    log_message "INFO" "OAuth2 authorization URL generation completed"
}

# Function to register user with custom member ID
register_user_with_id() {

    local auth_code=$1
    local user_id=$2
    
    # Validate CLIENT_ID and CLIENT_SECRET are set
    if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
        print_status "$RED" "❌ Error: CLIENT_ID and CLIENT_SECRET environment variables are required!"
        print_status "$RED" "💡 Please run: source polar_env.sh"
        log_message "ERROR" "CLIENT_ID and CLIENT_SECRET environment variables required for user registration"
        exit 1
    fi
    
    print_status "$BLUE" "🔐 Starting user registration process..."
    log_message "INFO" "Starting user registration with auth code: ${auth_code:0:10}... and user ID: ${user_id}"
    
    # Authenticate first
    print_status "$BLUE" "🔐 Authenticating with Polar API..."
    local access_token
    access_token=$(authenticate "$auth_code")
    local auth_result=$?
    
    if [ $auth_result -ne 0 ] || [ -z "$access_token" ]; then
        print_status "$RED" "🚫 Authentication failed - cannot register user"
        log_message "ERROR" "Authentication failed during user registration"
        exit 1
    fi
    
    print_status "$GREEN" "✅ Authentication successful"
    
    # Register user with custom member ID
    print_status "$BLUE" "👤 Registering user with ID: $user_id..."
    
    local response=$(curl -s -w "%{http_code}" -o /tmp/register_response.tmp \
        -X POST https://www.polaraccesslink.com/v3/users \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -H "Authorization: Bearer $access_token" \
        -d "{\"member-id\": \"$user_id\"}")
    
    local http_code="${response: -3}"
    local response_body=$(cat /tmp/register_response.tmp 2>/dev/null || echo "")
    rm -f /tmp/register_response.tmp
    
    print_status "$BLUE" "📋 Registration response: HTTP $http_code"
    log_message "INFO" "User registration request completed with HTTP status: $http_code"
    
    if [ "$http_code" -eq 200 ]; then
        print_status "$GREEN" "✅ User registration successful!"
        echo "   User ID: $user_id"
        echo "   Status: Registered successfully"
        log_message "INFO" "User registration successful for user ID: $user_id"
    elif [ "$http_code" -eq 409 ]; then
        print_status "$YELLOW" "⚠️  User already registered"
        echo "   User ID: $user_id"
        echo "   Status: Already exists"
        log_message "INFO" "User already registered for user ID: $user_id (HTTP 409)"
    elif [ "$http_code" -eq 403 ]; then
        print_status "$RED" "❌ User registration failed: consents not accepted"
        echo "   User ID: $user_id"
        echo "   Status: User has not accepted mandatory consents"
        log_message "ERROR" "User registration failed: consents not accepted (HTTP 403)"
        exit 1
    else
        print_status "$RED" "❌ User registration failed"
        echo "   User ID: $user_id"
        echo "   HTTP Status: $http_code"
        echo "   Response: $response_body"
        log_message "ERROR" "User registration failed (HTTP $http_code): $response_body"
        exit 1
    fi
    
    print_status "$GREEN" "🎉 User registration process completed!"
    log_message "INFO" "User registration process completed for user ID: $user_id"
}

# Function to get user information
get_user_info() {
    local auth_code=$1
    
    # Validate CLIENT_ID, CLIENT_SECRET, and MEMBER_ID are set
    if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ] || [ -z "$MEMBER_ID" ]; then
        print_status "$RED" "❌ Error: CLIENT_ID, CLIENT_SECRET, and MEMBER_ID environment variables are required!"
        print_status "$RED" "💡 Please run: source polar_env.sh"
        log_message "ERROR" "Environment variables required for user info retrieval"
        exit 1
    fi
    
    print_status "$BLUE" "🔐 Starting user info retrieval process..."
    log_message "INFO" "Starting user info retrieval with auth code: ${auth_code:0:10}... for user ID: ${MEMBER_ID}"
    
    # Authenticate first
    print_status "$BLUE" "🔐 Authenticating with Polar API..."
    local access_token
    access_token=$(authenticate "$auth_code")
    local auth_result=$?
    
    if [ $auth_result -ne 0 ] || [ -z "$access_token" ]; then
        print_status "$RED" "🚫 Authentication failed - cannot retrieve user info"
        log_message "ERROR" "Authentication failed during user info retrieval"
        exit 1
    fi
    
    print_status "$GREEN" "✅ Authentication successful"
    
    # Get user information
    print_status "$BLUE" "👤 Fetching user information for ID: $MEMBER_ID..."
    log_message "INFO" "Requesting user info from: https://www.polaraccesslink.com/v3/users/$MEMBER_ID"
    log_message "INFO" "Using access token: ${access_token:0:10}..."
    
    local response=$(curl -s -w "%{http_code}" -o /tmp/userinfo_response.tmp \
        -X GET "https://www.polaraccesslink.com/v3/users/$MEMBER_ID" \
        -H "Accept: application/json" \
        -H "Authorization: Bearer $access_token" \
        --connect-timeout 30 \
        --max-time 60)
    
    local curl_exit_code=$?
    local http_code="${response: -3}"
    local response_body=$(cat /tmp/userinfo_response.tmp 2>/dev/null || echo "")
    
    # Check for actual failures
    if [ $curl_exit_code -ne 0 ] || [ "$http_code" = "000" ] || [ -z "$http_code" ]; then
        print_status "$RED" "🚨 Curl command failed (exit code: $curl_exit_code)"
        log_message "ERROR" "Curl command failed with exit code: $curl_exit_code"
        
        # Test basic connectivity
        print_status "$BLUE" "🔍 Testing basic connectivity to Polar API..."
        local test_response=$(curl -s -w "%{http_code}" --connect-timeout 10 -I https://www.polaraccesslink.com/ || echo "CONNECTION_FAILED")
        print_status "$BLUE" "🔍 Connectivity test result: $test_response"
        log_message "INFO" "Connectivity test result: $test_response"
        
        rm -f /tmp/userinfo_response.tmp
        exit 1
    fi
    
    rm -f /tmp/userinfo_response.tmp
    
    print_status "$BLUE" "📋 User info response: HTTP $http_code"
    log_message "INFO" "User info request completed with HTTP status: $http_code"
    
    if [ "$http_code" -eq 200 ]; then
        print_status "$GREEN" "✅ User information retrieved successfully!"
        echo ""
        print_status "$BLUE" "👤 User Information:"
        
        # Parse and display user information
        local user_id=$(echo "$response_body" | grep -o '"polar-user-id":"[^"]*"' | cut -d'"' -f4)
        local member_id=$(echo "$response_body" | grep -o '"member-id":"[^"]*"' | cut -d'"' -f4)
        local first_name=$(echo "$response_body" | grep -o '"first-name":"[^"]*"' | cut -d'"' -f4)
        local last_name=$(echo "$response_body" | grep -o '"last-name":"[^"]*"' | cut -d'"' -f4)
        local birthdate=$(echo "$response_body" | grep -o '"birthdate":"[^"]*"' | cut -d'"' -f4)
        local gender=$(echo "$response_body" | grep -o '"gender":"[^"]*"' | cut -d'"' -f4)
        local weight=$(echo "$response_body" | grep -o '"weight":[0-9.]*' | cut -d':' -f2)
        local height=$(echo "$response_body" | grep -o '"height":[0-9.]*' | cut -d':' -f2)
        
        echo "   Polar User ID: ${user_id:-'N/A'}"
        echo "   Member ID: ${member_id:-'N/A'}"
        echo "   Name: ${first_name:-'N/A'} ${last_name:-'N/A'}"
        echo "   Birth Date: ${birthdate:-'N/A'}"
        echo "   Gender: ${gender:-'N/A'}"
        echo "   Weight: ${weight:-'N/A'} kg"
        echo "   Height: ${height:-'N/A'} cm"
        
        log_message "INFO" "User information retrieved successfully for user ID: $MEMBER_ID"
    elif [ "$http_code" -eq 204 ]; then
        print_status "$YELLOW" "⚠️  No user information found"
        echo "   User ID: $MEMBER_ID"
        echo "   Status: User not found or no data available"
        log_message "WARN" "No user information found for user ID: $MEMBER_ID (HTTP 204)"
    elif [ "$http_code" -eq 403 ]; then
        print_status "$RED" "❌ Access forbidden"
        echo "   User ID: $MEMBER_ID"
        echo "   Status: User has not accepted mandatory consents or access denied"
        log_message "ERROR" "Access forbidden for user info retrieval (HTTP 403)"
        exit 1
    else
        print_status "$RED" "❌ Failed to retrieve user information"
        echo "   User ID: $MEMBER_ID"
        echo "   HTTP Status: $http_code"
        
        echo "   Response: $response_body"
        
        log_message "ERROR" "Failed to retrieve user info (HTTP $http_code): $response_body"
        exit 1
    fi
    
    print_status "$GREEN" "🎉 User info retrieval process completed!"
    log_message "INFO" "User info retrieval process completed for user ID: $MEMBER_ID"
}

# Function to validate and show configuration
validate_configuration() {
    # Validate required values are not empty
    if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ] || [ -z "$MEMBER_ID" ]; then
        print_status "$RED" "❌ Error: Required environment variables are not set!"
        print_status "$RED" "💡 Please run: source polar_env.sh"
        print_status "$RED" "💡 Or set: CLIENT_ID, CLIENT_SECRET, MEMBER_ID"
        log_message "ERROR" "Missing required environment variables"
        exit 1
    fi
    
    print_status "$BLUE" "🔧 Configuration loaded from environment:"
    echo "   CLIENT_ID: ${CLIENT_ID}"
    echo "   CLIENT_SECRET: ${CLIENT_SECRET:0:10}..."
    echo "   MEMBER_ID: ${MEMBER_ID}"
    if [ -n "$AUTH_CODE" ]; then
        echo "   AUTH_CODE: ${AUTH_CODE:0:10}... (${#AUTH_CODE} characters)"
    else
        echo "   AUTH_CODE: (not set - will require parameter)"
    fi
    
    log_message "INFO" "Configuration loaded from environment - CLIENT_ID: ${CLIENT_ID}, CLIENT_SECRET: ${CLIENT_SECRET:0:10}..., MEMBER_ID: ${MEMBER_ID}, AUTH_CODE: ${AUTH_CODE:+set (${#AUTH_CODE} chars)}"
}

# Function to log messages
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to authenticate and get access token
authenticate() {
    local auth_code=$1
    
    echo "🔐 Authenticating with Polar API..." >&2
    log_message "INFO" "Starting authentication process with authorization code: ${auth_code:0:10}..."
    
    # Encode client credentials
    echo "🔑 Encoding client credentials..." >&2
    local credentials=$(echo -n "${CLIENT_ID}:${CLIENT_SECRET}" | base64)
    log_message "INFO" "Client credentials encoded for Basic authentication"
    
    # Get access token with detailed response
    echo "📡 Making OAuth2 token request..." >&2
    log_message "INFO" "Making OAuth2 token request to polarremote.com/v2/oauth2/token"
    local response=$(curl -s -w "%{http_code}" -o /tmp/auth_response.tmp \
        -X POST https://polarremote.com/v2/oauth2/token \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -H "Accept: application/json" \
        -H "Authorization: Basic $credentials" \
        --data-urlencode "grant_type=authorization_code" \
        --data-urlencode "code=$auth_code")
    
    local http_code="${response: -3}"
    local response_body=$(cat /tmp/auth_response.tmp 2>/dev/null || echo "")
    rm -f /tmp/auth_response.tmp
    
    log_message "INFO" "OAuth2 token request completed with HTTP status: $http_code"
    
    # Extract access token from response
    local access_token=$(echo "$response_body" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
    
    if [ "$http_code" -eq 200 ] && [ -n "$access_token" ]; then
        echo -e "${GREEN}✅ Authentication successful!${NC}" >&2
        log_message "INFO" "Authentication successful - received access token: ${access_token:0:10}..."
        log_message "INFO" "Token type: Bearer"
        echo "$access_token"
        return 0
    else
        echo -e "${RED}❌ Authentication failed!${NC}" >&2
        if [ "$http_code" -eq 400 ]; then
            echo -e "${RED}💡 Hint: Check your authorization code - it may be expired or invalid${NC}" >&2
            log_message "ERROR" "Authentication failed (HTTP 400): Invalid request - check authorization code"
        elif [ "$http_code" -eq 401 ]; then
            echo -e "${RED}💡 Hint: Client credentials are invalid${NC}" >&2
            log_message "ERROR" "Authentication failed (HTTP 401): Invalid client credentials"
        elif [ "$http_code" -eq 403 ]; then
            echo -e "${RED}💡 Hint: Access forbidden - check permissions${NC}" >&2
            log_message "ERROR" "Authentication failed (HTTP 403): Access forbidden"
        else
            echo -e "${RED}💡 HTTP Status: $http_code${NC}" >&2
            log_message "ERROR" "Authentication failed (HTTP $http_code): $response_body"
        fi
        log_message "ERROR" "Failed to obtain access token from OAuth2 response"
        return 1
    fi
}

# Function to register user (if needed)
register_user() {
    local access_token=$1
    
    print_status "$BLUE" "👤 Registering user..."
    
    local response=$(curl -s -w "%{http_code}" -o /tmp/register_response.tmp \
        -X POST https://www.polaraccesslink.com/v3/users \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -H "Authorization: Bearer $access_token" \
        -d "{\"member-id\": \"$MEMBER_ID\"}")
    
    local http_code="${response: -3}"
    local response_body=$(cat /tmp/register_response.tmp 2>/dev/null || echo "")
    rm -f /tmp/register_response.tmp
    
    if [ "$http_code" -eq 200 ]; then
        print_status "$GREEN" "✅ User registration successful"
        log_message "INFO" "User registration successful (HTTP 200)"
    elif [ "$http_code" -eq 409 ]; then
        print_status "$YELLOW" "⚠️  User already registered (continuing)"
        log_message "INFO" "User already registered (HTTP 409)"
    elif [ "$http_code" -eq 403 ]; then
        print_status "$RED" "❌ User has not accepted mandatory consents"
        log_message "ERROR" "User registration failed: consents not accepted (HTTP 403)"
        exit 1
    else
        print_status "$RED" "❌ User registration failed (HTTP $http_code)"
        log_message "ERROR" "User registration failed (HTTP $http_code): $response_body"
        exit 1
    fi
}

# Function to download heart rate data for a specific date
download_heart_rate_data() {
    local access_token=$1
    local date=$2
    local output_file="$OUTPUT_DIR/$date.json"
    
    # Skip if file already exists
    if [ -f "$output_file" ]; then
        print_status "$YELLOW" "⏭️  Skipping $date (file already exists)"
        return 0
    fi
    
    print_status "$BLUE" "📊 Downloading data for $date..."
    
    local response=$(curl -s -w "%{http_code}" -o "$output_file.tmp" \
        -X GET "https://www.polaraccesslink.com/v3/users/continuous-heart-rate/$date" \
        -H "Accept: application/json" \
        -H "Authorization: Bearer $access_token")
    
    local http_code="${response: -3}"
    
    if [ "$http_code" -eq 200 ]; then
        mv "$output_file.tmp" "$output_file"
        print_status "$GREEN" "✅ Downloaded $date"
        log_message "INFO" "Successfully downloaded data for $date"
        return 0
    elif [ "$http_code" -eq 204 ]; then
        rm -f "$output_file.tmp"
        print_status "$YELLOW" "⚠️  No data available for $date"
        log_message "WARN" "No data available for $date (HTTP 204)"
        return 0
    else
        rm -f "$output_file.tmp"
        print_status "$RED" "❌ Failed to download $date (HTTP $http_code)"
        log_message "ERROR" "Failed to download data for $date (HTTP $http_code)"
        return 1
    fi
}

# Function to generate all dates for the last 30 days
generate_recent_dates() {
    # Generate dates for the last 30 days (Polar API limitation)
    for i in $(seq 0 29); do
        date -v-${i}d +%Y-%m-%d
    done
}

# Main function
main() {
    local auth_code=""
    
    # Check if no arguments provided
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --chr)
                if [ -n "$2" ] && [[ "$2" != --* ]]; then
                    # Auth code provided as parameter
                    auth_code="$2"
                    shift 2
                else
                    # No auth code parameter, use environment variable
                    auth_code="$AUTH_CODE"
                    shift 1
                fi
                ;;
            --ru)
                local ru_auth_code=""
                local ru_user_id=""
                
                if [ -n "$2" ] && [[ "$2" != --* ]]; then
                    if [ -n "$3" ] && [[ "$3" != --* ]]; then
                        # Both auth code and user ID provided as parameters
                        ru_auth_code="$2"
                        ru_user_id="$3"
                        shift 3
                    else
                        # Only one parameter provided, assume it's user_id and use AUTH_CODE env var
                        ru_auth_code="$AUTH_CODE"
                        ru_user_id="$2"
                        shift 2
                    fi
                else
                    print_status "$RED" "❌ Error: --ru flag requires at least a user ID"
                    echo "Usage: $0 --ru [authorization_code] <user_id>"
                    echo "Use --help for usage information"
                    exit 1
                fi
                
                if [ -z "$ru_auth_code" ]; then
                    print_status "$RED" "❌ Error: Authorization code required (parameter or AUTH_CODE env var)"
                    echo "Use --help for usage information"
                    exit 1
                fi
                
                register_user_with_id "$ru_auth_code" "$ru_user_id"
                exit 0
                ;;
            --gui)
                local gui_auth_code=""
                
                if [ -n "$2" ] && [[ "$2" != --* ]]; then
                    # Auth code provided as parameter
                    gui_auth_code="$2"
                    shift 2
                else
                    # No auth code parameter, use environment variable
                    gui_auth_code="$AUTH_CODE"
                    shift 1
                fi
                
                if [ -z "$gui_auth_code" ]; then
                    print_status "$RED" "❌ Error: Authorization code required (parameter or AUTH_CODE env var)"
                    echo "Usage: $0 --gui [authorization_code]"
                    echo "Use --help for usage information"
                    exit 1
                fi
                
                get_user_info "$gui_auth_code"
                exit 0
                ;;
            --gac)
                get_authorization_token
                exit 0
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                print_status "$RED" "❌ Error: Unknown option '$1'"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Validate authorization code is provided (from parameter or environment)
    if [ -z "$auth_code" ]; then
        if [ -n "$AUTH_CODE" ]; then
            auth_code="$AUTH_CODE"
            print_status "$BLUE" "📋 Using authorization code from AUTH_CODE environment variable"
        else
            print_status "$RED" "❌ Error: Authorization code is required"
            print_status "$RED" "💡 Set AUTH_CODE environment variable or use --chr <code>"
            echo "Use --help for usage information"
            exit 1
        fi
    fi
    
    # Initialize
    print_status "$BLUE" "🚀 Starting Polar Heart Rate Data Download for last 30 days"
    log_message "INFO" "Starting download process with auth code: ${auth_code:0:10}..."
    
    # Validate configuration
    validate_configuration
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Authenticate and get access token
    print_status "$BLUE" "🔐 Starting authentication process..."
    local access_token
    access_token=$(authenticate "$auth_code")
    local auth_result=$?
    
    if [ $auth_result -ne 0 ]; then
        print_status "$RED" "🚫 Authentication failed - stopping download process"
        log_message "ERROR" "Authentication process failed, exiting script"
        exit 1
    fi
    
    if [ -z "$access_token" ]; then
        print_status "$RED" "🚫 No access token received - stopping download process"
        log_message "ERROR" "No access token received from authentication"
        exit 1
    fi
    
    print_status "$GREEN" "🎉 Authentication completed successfully - proceeding to download data"
    log_message "INFO" "Authentication completed, access token obtained: ${access_token:0:10}..."
    
    # Generate all dates for the last 30 days
    print_status "$BLUE" "📅 Generating dates for the last 30 days..."
    local temp_file=$(mktemp)
    generate_recent_dates > "$temp_file"
    local dates=()
    while IFS= read -r line; do
        [ -n "$line" ] && dates+=("$line")
    done < "$temp_file"
    rm -f "$temp_file"
    
    print_status "$BLUE" "📅 Processing ${#dates[@]} recent days..."
    
    # Download data for each date
    local success_count=0
    local skip_count=0
    local error_count=0
    
    for date in "${dates[@]}"; do
        # Skip empty dates
        if [ -z "$date" ]; then
            log_message "WARN" "Skipping empty date"
            continue
        fi
        
        if download_heart_rate_data "$access_token" "$date"; then
            if [ -f "$OUTPUT_DIR/$date.json" ]; then
                ((success_count++))
            else
                ((skip_count++))
            fi
        else
            ((error_count++))
        fi
        
        # Small delay to avoid rate limiting
        sleep 0.1
    done
    
    # Summary
    print_status "$GREEN" "🎉 Download completed!"
    print_status "$GREEN" "📊 Summary:"
    print_status "$GREEN" "   ✅ Successfully downloaded: $success_count files"
    print_status "$YELLOW" "   ⏭️  Skipped (no data): $skip_count days"
    print_status "$RED" "   ❌ Errors: $error_count days"
    
    log_message "INFO" "Download completed. Success: $success_count, Skipped: $skip_count, Errors: $error_count"
    
    if [ $error_count -eq 0 ]; then
        print_status "$GREEN" "🎊 All downloads completed successfully!"
        exit 0
    else
        print_status "$YELLOW" "⚠️  Some downloads failed. Check $LOG_FILE for details."
        exit 1
    fi
}

# Run main function with all arguments
main "$@" 