import requests

def get_codeforces_rating(handle):
    url = f"https://codeforces.com/api/user.info?handles={handle}"
    try:
        response = requests.get(url)
        response.raise_for_status()
        data = response.json()
        if data["status"] == "OK":
            user_info = data["result"][0]
            print(f"{user_info.get('rating', 'Unrated')}/{user_info.get('maxRating', 'Unrated')}")
    except requests.exceptions.RequestException as e:
        print("Error fetching data")

if __name__ == "__main__":
    handle = "feironox5"
    get_codeforces_rating(handle)
