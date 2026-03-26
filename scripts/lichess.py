import requests


def get_lichess_rating(username):
    url = f"https://lichess.org/api/user/{username}"
    try:
        response = requests.get(url)
        # response.raise_for_status()
        data = response.json()
        if data:
            blitz_rating = data.get("perfs", {}).get("blitz", {}).get("rating", None)
            rapid_rating = data.get("perfs", {}).get("rapid", {}).get("rating", None)
            classical_rating = (
                data.get("perfs", {}).get("classical", {}).get("rating", None)
            )
            if (
                blitz_rating is not None
                and rapid_rating is not None
                and classical_rating is not None
            ):
                print(f"B{blitz_rating}/R{rapid_rating}/C{classical_rating}")
    except requests.exceptions.RequestException as e:
        print("Error fetching data")


if __name__ == "__main__":
    handle = "lostinwinelands"
    get_lichess_rating(handle)
