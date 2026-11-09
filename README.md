# Sameh & Mazen barber shop website

Live link: https://kareemcrafts.github.io/sameh-mazen/

## What is here
- `index.html`: the whole website (home, booking on WhatsApp, stamp card, haircut finder, gift cards, barber page)
- `img/`: logo and shop photos
- `setup/setup.sql`: the database setup for Supabase
- `setup/sameh-mazen-qr-poster.png` and `.pdf`: the QR poster for the shop

## Setup (one time)
1. In Supabase, open **SQL Editor**, then **New query**.
2. Open `setup/setup.sql`. Change `CHANGE-ME@example.com` (last line) to the barber's email.
3. Paste everything and press **Run**.
4. In Supabase, open **Authentication → Users → Add user → Create new user**.
   Use the same email and a strong password. Tick **Auto Confirm User**.
5. Done. The barber logs in at the bottom of the website ("Barber page").

## Change things later
In `index.html`, look for `CONFIG` near the top of the script:
- `whatsapp`: the shop's WhatsApp number
- prices are in `SERVICES`
