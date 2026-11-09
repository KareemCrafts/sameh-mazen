# Sameh & Mazen barber shop website

Live link: https://kareemcrafts.github.io/sameh-mazen/

## What is here
- `index.html`: the whole website (home, booking on WhatsApp, stamp card, haircut finder, gift cards, barber page)
- `img/`: logo and shop photos
- `setup/setup.sql`: the database setup for Supabase
- `setup/sameh-mazen-qr-poster.png` and `.pdf`: the QR poster for the shop

## Setup (one time)
1. In Supabase: **Authentication → Users → Add user → Create new user**.
   Write the barber's email and a password. Tick **Auto Confirm User**. Press **Create user**.
2. In Supabase: **SQL Editor**. Paste everything from `setup/setup.sql` and press **Run**.
3. Done. The barber logs in at the bottom of the website ("Barber page").

## Change things later
In `index.html`, look for `CONFIG` near the top of the script:
- `whatsapp`: the shop's WhatsApp number
- prices are in `SERVICES`
