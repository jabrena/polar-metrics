# polar-metrics

## Generate data

```bash
# Step 1: Register environment variables
export CLIENT_ID="xxx"
export CLIENT_SECRET="yyy"
export MEMBER_ID="zzz"

# Step 2: Get Authorization code
./polar_heart_rate_downloader.sh --gac

# Step 3: Export Authorization code into a Environment variable
export AUTH_CODE="www"

# Step 4: Register user
./polar_heart_rate_downloader.sh --ru

# Step 5: Retrieve user information
./polar_heart_rate_downloader.sh --gui

# Step 6: Retrieve Continuous heart rate
./polar_heart_rate_downloader.sh --chr
```

## Visualize

```bash
jwebserver -p 8005 -d "$(pwd)/docs/"
```

## Further information

- https://www.polar.com/accesslink-api
