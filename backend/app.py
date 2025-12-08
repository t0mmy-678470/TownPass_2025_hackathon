import asyncio
import time
import random
from flask import Flask, request, jsonify
import whois  
from urllib.parse import urlparse  
from datetime import datetime 
import pytz
import parse
import joblib
import requests
import socket
import ipaddress
import geocoder
import redis
import json

app = Flask(__name__)

# Wrap Redis initialization in try-except to prevent crash on startup if Redis is down
try:
    r = redis.Redis(host='localhost', port=6379, db=0)
except Exception as e:
    print(f"Redis initialization failed: {e}")
    r = None

# --- Your Test Functions ---

async def check_phishing_db(url: str) -> dict:
    """Simulates checking a URL against a phishing database."""
    try:
        print(f"START: check_phishing_db for {url}")
        await asyncio.sleep(random.uniform(0.5, 1.5))
        
        is_fraud = "example.com" in url 
        print(f"END: check_phishing_db for {url}")
        
        return {
            "test_name": "phishing_database",
            "test_result": "URL found in DB" if is_fraud else "URL clear",
            "is_fraud": is_fraud
        }
    except Exception as e:
        print(f"Error in check_phishing_db: {e}")
        return {
            "test_name": "phishing_database",
            "test_result": "Error checking database",
            "is_fraud": False,
            "error": str(e)
        }

async def analyze_content_keywords(url: str) -> dict:
    """Simulates downloading and scanning page content for keywords."""
    try:
        print(f"START: analyze_content_keywords for {url}")
        await asyncio.sleep(random.uniform(1.0, 2.0))
        
        is_fraud = "bad-stuff.com" in url 
        print(f"END: analyze_content_keywords for {url}")
        
        return {
            "test_name": "content_analysis",
            "test_result": "Fraudulent keywords found",
            "is_fraud": is_fraud
        }
    except Exception as e:
        print(f"Error in analyze_content_keywords: {e}")
        return {
            "test_name": "content_analysis",
            "test_result": "Error analyzing content",
            "is_fraud": False,
            "error": str(e)
        }

def _get_whois_data(domain: str) -> dict:
    """
    This is a BLOCKING function that runs the WHOIS query.
    """
    try:
        w = whois.whois(domain)

        if not w.creation_date:
            return {"country": None, "creation_date": None, "error": "No WHOIS data found"}

        creation_date = w.creation_date
        if isinstance(creation_date, list):
            creation_date = creation_date[0] 

        country = w.country
        if isinstance(country, list):
            country = country[0] 

        return {"country": country, "creation_date": creation_date, "error": None}
    
    except Exception as e:
        return {"country": None, "creation_date": None, "error": str(e)}

def check_domain_info(url: str) -> dict:
    """
    Checks domain registration date (age) and country via WHOIS.
    """
    print(f"START: check_domain_info for {url}")
    
    try:
        parsed_url = urlparse(url)
        domain = parsed_url.hostname
        if not domain:
            raise ValueError("Could not parse domain from URL")
        
        if domain.startswith('www.'):
            domain = domain[4:]
    except Exception as e:
        return {
            "test_result": f"Invalid URL format: {e}",
            "is_fraud": True,
            "is_gov": False,
            "is_edu": False
        }

    try:
        whois_data = _get_whois_data(domain)
        print(whois_data)
        
        is_gov = False
        if domain and (domain.endswith("gov.tw") or domain.endswith("gov.taipei")):
            is_gov = True
            
        is_edu = False
        if domain and domain.endswith("edu.tw"):
            is_edu = True

        print(f"END: check_domain_info for {domain}")
        
        if whois_data["error"]:
            if is_gov or is_edu:
                is_fraud = False
            else:
                is_fraud = True
            return {
                "test_result": f"WHOIS error: {whois_data['error']}",
                "is_fraud": is_fraud,
                "is_gov": is_gov,
                "is_edu": is_edu
            }

        is_fraud = False
        result_parts = []
        
        if whois_data["country"]:
            result_parts.append(f"Country: {whois_data['country']}")
        
        if whois_data["creation_date"]:
            creation_date = whois_data["creation_date"]
            now = datetime.now()
            # Handle potential timezone issues safely
            try:
                if creation_date.tzinfo is None:
                     # If naive, make it aware (assuming UTC or similar)
                     creation_date = creation_date.replace(tzinfo=pytz.timezone('UTC'))
                now = now.replace(tzinfo=pytz.timezone('UTC'))
            except Exception:
                pass # Continue if timezone conversion fails
            
            domain_age_days = (now - creation_date).days
            
            result_parts.append(f"Created: {creation_date.strftime('%Y-%m-%d')} ({domain_age_days} days old)")
            
            if domain_age_days < 180:
                is_fraud = True
        else:
            is_fraud = True
            result_parts.append("No creation date found.")

        return {
            "test_result": {
                "Country": whois_data['country'],
                "Created": whois_data['creation_date'].strftime('%Y-%m-%d') if whois_data['creation_date'] else "Unknown",
                "Domain_age": domain_age_days/30 if 'domain_age_days' in locals() else 0
            },
            "is_fraud": is_fraud,
            "is_gov": is_gov,
            "is_edu": is_edu
        }
    except Exception as e:
        # Fallback for unexpected errors in logic
        return {
            "test_result": f"Internal Error: {str(e)}",
            "is_fraud": False, 
            "is_gov": False, 
            "is_edu": False
        }

async def ml_testing(sample):
    try:
        model = joblib.load("phishing_model.joblib")
        # y_probe = [[probe_of_-1, probe_of_1], ...]
        y_probe = model.predict_proba(sample)   
        # y_pred = model.predict(sample) 
        return y_probe
    except FileNotFoundError:
        print("ML Model file not found.")
        return [[0.0, 0.0]] # Return neutral probability to avoid index errors
    except Exception as e:
        print(f"ML Testing Error: {e}")
        return [[0.0, 0.0]]

async def thirdparty_testing(url):
    try:
        api_url = "https://link-checker.nordvpn.com/v1/public-url-checker/check-url"
        payload = {"url": url}
        
        # Add timeout to prevent hanging
        response = requests.post(api_url, json=payload, timeout=5)
        response.raise_for_status() # Raise error for bad status codes (4xx, 5xx)
        return response.json()
    except Exception as e:
        print(f"Thirdparty API Error: {e}")
        # Return a safe default structure that mimics the API so logic downstream doesn't break
        return {"category": -1, "error": str(e)} 

async def ip_location_testing(url):
    try:
        parsed_url = urlparse(url)
        hostname = str(parsed_url.hostname)
        if not hostname:
             return "Invalid Hostname", None
             
        ip_address = socket.gethostbyname(hostname)
        g_ip = geocoder.ip(ip_address)
        return g_ip.country, ip_address
    except Exception as e:
        print(f"IP Location Error: {e}")
        return "Unknown", None

def is_redis_connected(r: redis.Redis) -> bool:
    if r is None:
        return False
    try:
        return r.ping()
    except (redis.ConnectionError, redis.TimeoutError, Exception):
        return False
    
def fetch_cache(url):
    try:
        # 1️⃣ 先查 Redis cache
        if is_redis_connected(r) == False:
            return None
        cached = r.get(url)
        if cached:
            print("✅ 使用快取資料")
            return json.loads(cached)
        else:
            return None
    except Exception as e:
        print(f"Cache Fetch Error: {e}")
        return None
    
def save_cache(key, value):
    try:
        if is_redis_connected(r) == False:
            return False
        # 設定快取有效期限 (例如 1 小時)
        r.setex(key, 3600, json.dumps(value))
        return True
    except Exception as e:
        print(f"Cache Save Error: {e}")
        return False

# --- The API Endpoint ---

@app.route('/test_url', methods=['POST'])
async def test_url():
    """
    Receives a URL, runs all fraud tests in parallel,
    and returns a list of results.
    """
    try:
        data = request.get_json()

        if not data or 'url' not in data:
            return jsonify({"error": "Missing 'url' in request body"}), 400
        url_to_test = data['url']

        print(f'check cache for {url_to_test}')
        try:
            results = fetch_cache(url_to_test)
        except Exception:
            results = None # Fallback if cache logic fails completely

        if results is None:
            print('cache not found')
        else:
            print('cache found')
            return jsonify(results), 200 # Use jsonify for safe serialization
        
        print(f"--- Firing tests for {url_to_test} ---")
        results = []
        start_time = time.time()

        # 1. Third Party Test
        try:
            thirdparty_testing_result = await thirdparty_testing(url_to_test)
            # Check if key exists to prevent KeyError
            if thirdparty_testing_result.get("category") == 1:
                results.append({"nordVPN":"safe"})
            else:
                results.append({"nordVPN":"unsafe"})
        except Exception as e:
             results.append({"nordVPN": f"error: {str(e)}"})

        # 2. ML Test
        try:
            features = parse.extract_features(url_to_test)
            ml_result = await ml_testing([features])
            # Ensure ml_result has the expected structure
            if ml_result and len(ml_result) > 0 and len(ml_result[0]) > 0:
                if ml_result[0][0] >= 0.5:
                    results.append({"MLtest":"unsafe"})
                else:
                    results.append({"MLtest":"safe"})
            else:
                 results.append({"MLtest":"unknown"})
        except Exception as e:
             print(f"ML Processing failed: {e}")
             results.append({"MLtest": "error"})

        # 3. Domain Info Test
        try:
            info_result = check_domain_info(url_to_test)
            results.append(info_result)
        except Exception as e:
            results.append({"test_result": f"error: {str(e)}", "is_fraud": True})

        # 4. IP Location Test
        try:
            server_country, ip_address = await ip_location_testing(url_to_test)
            
            # Check if ip_address is valid before passing to ipaddress module
            if ip_address:
                try:
                    if ipaddress.ip_address(ip_address):
                        results.append({"ServerLocation": server_country})
                except ValueError:
                    results.append({"ServerLocation": "fail to parse ip"})
            else:
                results.append({"ServerLocation": "fail to get an ip"})
        except Exception as e:
             results.append({"ServerLocation": "error"})

        
        # results = await asyncio.gather(*tasks)
        
        end_time = time.time()
        print(f"--- All tests completed in {end_time - start_time:.2f} seconds ---")

        if save_cache(url_to_test, results) == False:
            print('save cache failed')
        else:
            print('save cache success')

        return jsonify(results), 200
    
    except Exception as e:
        print(f"CRITICAL API ERROR: {e}")
        # Return a JSON error so frontend doesn't get a raw 500 HTML page
        return jsonify([{"error": "Internal Server Error", "details": str(e)}]), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8001, debug=True)
