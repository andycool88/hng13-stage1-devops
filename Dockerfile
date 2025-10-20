# Use a lightweight official Nginx image as the base
FROM nginx:alpine

# Copy all your website's static files into the Nginx public directory
COPY . /usr/share/nginx/html
