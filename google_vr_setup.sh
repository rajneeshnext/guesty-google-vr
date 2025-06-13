#!/usr/bin/env bash
set -e

# Load credentials
if [ -f .env ]; then
  source .env
else
  echo "❌ Please create a .env file with CLIENT_ID and CLIENT_SECRET"
  exit 1
fi

# Ensure jq is installed
if ! command -v jq &> /dev/null; then
  echo "❌ 'jq' is required but not installed. Install it and re-run."
  exit 1
fi

# Variables
LISTING_ID="67503ac628bc3c0011e673f6"
CHECKIN="2025-06-17"
CHECKOUT="2025-06-19"
GUESTS=2

# Step 1: Get OAuth Token
echo "→ Getting access token..."
TOKEN=$(curl -s \
  --request POST https://booking.guesty.com/oauth2/token \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "scope=booking_engine:api" \
  --data-urlencode "client_id=${CLIENT_ID}" \
  --data-urlencode "client_secret=${CLIENT_SECRET}" \
  | jq -r .access_token)

[ -n "$TOKEN" ] && echo "✅ Token retrieved" || { echo "❌ Failed to retrieve token"; exit 1; }

# Step 2: Create Reservation Quote
echo "→ Creating reservation quote..."
RESP=$(curl -s -w "\n%{http_code}" -X POST \
  https://booking.guesty.com/api/reservations/quotes \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  --data "{
    \"listingId\":\"$LISTING_ID\",
    \"checkInDateLocalized\":\"$CHECKIN\",
    \"checkOutDateLocalized\":\"$CHECKOUT\",
    \"guestsCount\":$GUESTS
  }")

BODY=$(echo "$RESP" | sed '$d')
CODE=$(echo "$RESP" | tail -n1)
[ "$CODE" = "200" -o "$CODE" = "201" ] && echo "✅ Quote created" || { echo "❌ Quote creation failed ($CODE)"; echo "$BODY"; exit 1; }

QUOTE_ID=$(echo "$BODY" | jq -r .id)
echo "→ QUOTE_ID=$QUOTE_ID"

# Step 3: Create Instant Reservation
echo "→ Creating instant reservation..."
HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  "https://booking.guesty.com/api/reservations/quotes/$QUOTE_ID/instant-reservations" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  --data '{}')

[ "$HTTP" = "200" -o "$HTTP" = "302" ] && echo "✅ Instant reservation complete" || { echo "❌ Instant reservation failed ($HTTP)"; exit 1; }

# Step 4: Configure Google Metasearch
echo "→ Updating Google VR configuration..."
HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
  https://booking.guesty.com/api/metasearch/pointofsale/google/config \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  --data '{
    "url":"https://www.remotlys.com/properties/(PARTNER-HOTEL-ID)?minOccupancy=(NUM-GUESTS)&checkIn=(CHECKINYEAR)-(CHECKINMONTH)-(CHECKINDAY)&checkOut=(CHECKOUTYEAR)-(CHECKOUTMONTH)-(CHECKOUTDAY)&pointofsale=google"
  }')

[ "$HTTP" = "200" ] && echo "✅ Google VR config updated" || { echo "❌ Config update failed ($HTTP)"; exit 1; }

echo ""
echo "🎉 All steps completed successfully!"
echo "Next: Go to Guesty → Growth → Distribution → Google → Connect Listings."
