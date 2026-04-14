FROM alpine:3.14

RUN apk add --no-cache nginx

COPY nginx.conf /etc/nginx/nginx.conf

CMD ["nginx", "-g", "daemon off;"]