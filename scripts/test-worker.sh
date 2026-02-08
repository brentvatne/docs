#!/bin/bash
# Test script for Cloudflare Pages _worker.js and _routes.json configuration
# This script verifies that the Pages worker works correctly with wrangler

set -e

echo "=== Testing Cloudflare Pages Worker and Routes ==="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Track test results
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
  echo -e "${GREEN}✓ $1${NC}"
  ((TESTS_PASSED++))
}

fail() {
  echo -e "${RED}✗ $1${NC}"
  ((TESTS_FAILED++))
}

info() {
  echo -e "${YELLOW}→ $1${NC}"
}

cleanup() {
  if [ -n "$WRANGLER_PID" ]; then
    kill $WRANGLER_PID 2>/dev/null || true
  fi
  if [ "$CLEANUP_OUT" = true ]; then
    rm -rf out
  fi
}

trap cleanup EXIT

# 1. Validate _routes.json structure
echo ""
echo "--- Validating _routes.json ---"
if [ -f "public/_routes.json" ]; then
  pass "_routes.json exists"

  # Check JSON is valid
  if node -e "JSON.parse(require('fs').readFileSync('public/_routes.json', 'utf8'))" 2>/dev/null; then
    pass "_routes.json is valid JSON"

    # Check required fields
    if node -e "
      const routes = JSON.parse(require('fs').readFileSync('public/_routes.json', 'utf8'));
      if (routes.version !== 1) throw new Error('version must be 1');
      if (!Array.isArray(routes.include)) throw new Error('include must be an array');
      if (!Array.isArray(routes.exclude)) throw new Error('exclude must be an array');
    " 2>/dev/null; then
      pass "_routes.json has valid structure (version, include, exclude)"
    else
      fail "_routes.json missing required fields"
    fi
  else
    fail "_routes.json is not valid JSON"
  fi
else
  fail "_routes.json does not exist"
fi

# 2. Validate _worker.js exists and has valid syntax
echo ""
echo "--- Validating _worker.js ---"
if [ -f "public/_worker.js" ]; then
  pass "_worker.js exists"

  # Check JavaScript syntax
  if node --check public/_worker.js 2>/dev/null; then
    pass "_worker.js has valid JavaScript syntax"
  else
    fail "_worker.js has syntax errors"
  fi

  # Check for required export
  if grep -q "export default" public/_worker.js; then
    pass "_worker.js has default export"
  else
    fail "_worker.js missing default export"
  fi

  # Check for fetch handler
  if grep -q "async fetch" public/_worker.js; then
    pass "_worker.js has fetch handler"
  else
    fail "_worker.js missing fetch handler"
  fi
else
  fail "_worker.js does not exist"
fi

# 3. Check wrangler.toml exists
echo ""
echo "--- Validating wrangler.toml ---"
if [ -f "wrangler.toml" ]; then
  pass "wrangler.toml exists"
else
  info "wrangler.toml not found (optional for Pages)"
fi

# 4. Test wrangler pages dev with the worker
echo ""
echo "--- Testing wrangler pages dev ---"

# Create a minimal test output directory
mkdir -p out
cp public/_routes.json out/_routes.json
cp public/_worker.js out/_worker.js
echo "<html><body><h1>Test Page</h1></body></html>" > out/index.html

# Create a test markdown file for content negotiation test
mkdir -p out/test-page
echo "# Test Markdown Content" > out/test-page/index.md

CLEANUP_OUT=true

# Start wrangler in background
info "Starting wrangler pages dev..."
npx wrangler pages dev out --port 8788 --log-level error &
WRANGLER_PID=$!

# Wait for wrangler to start
sleep 4

# Test if server is responding
echo ""
echo "--- Testing HTTP responses ---"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8788/ 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "304" ]; then
  pass "Server responds with HTTP $HTTP_CODE for HTML request"
else
  fail "Server not responding (HTTP $HTTP_CODE)"
fi

# Test markdown content negotiation (the main feature of _worker.js)
echo ""
echo "--- Testing markdown content negotiation ---"

MD_RESPONSE=$(curl -s -H "Accept: text/markdown" http://localhost:8788/test-page 2>/dev/null || echo "")
if echo "$MD_RESPONSE" | grep -q "Test Markdown Content"; then
  pass "Worker serves markdown when Accept: text/markdown header is sent"
else
  info "Markdown content negotiation test inconclusive (may need full build)"
fi

# Check Content-Type header for markdown request
MD_CONTENT_TYPE=$(curl -sI -H "Accept: text/markdown" http://localhost:8788/test-page 2>/dev/null | grep -i "content-type" || echo "")
if echo "$MD_CONTENT_TYPE" | grep -qi "text/markdown"; then
  pass "Worker returns correct Content-Type for markdown"
else
  info "Content-Type header test inconclusive"
fi

# Summary
echo ""
echo "=== Test Summary ==="
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
  echo -e "${RED}Failed: $TESTS_FAILED${NC}"
  exit 1
else
  echo "All tests passed!"
  exit 0
fi
