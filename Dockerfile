############################
# For  Build Stage
############################
FROM public.ecr.aws/docker/library/node:20.17-slim AS builder
WORKDIR /app

ARG APP_ENV=production
ENV APP_ENV ${APP_ENV}

COPY . .
# npm install & build
RUN npm ci && npm run build

############################
# For  Runner Stage
############################
FROM public.ecr.aws/docker/library/node:20.17-slim AS runner

# # install Lambda Insights
# RUN apt-get update && apt-get install -y curl rpm && \
#     curl -O https://lambda-insights-extension.s3-ap-northeASt-1.amazonaws.com/amazon_linux/lambda-insights-extension.rpm && \
#     rpm -U lambda-insights-extension.rpm && \
#     rm -f lambda-insights-extension.rpm

# # install Lambda Web Adapter
# COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:0.8.3 /lambda-adapter /opt/extensions/lambda-adapter

ARG APP_ENV=production
ENV APP_ENV ${APP_ENV}
ARG PM2_VERSION=5.4.1
ENV TZ JST-9
ENV PORT=8080

WORKDIR /app

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/ecosystem4docker.config.js ./ecosystem.config.js
COPY --from=builder /app/next.config.js ./next.config.js
# COPY --from=builder /app/public ./public/
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

VOLUME /tmp/
RUN mkdir -p /tmp/cache
RUN ln -s /tmp/cache ./.next/cache
# CMD exec ./run.sh

RUN npm i pm2@${PM2_VERSION} -g
CMD pm2-runtime start ecosystem.config.js -- --env ${APP_ENV} -i max