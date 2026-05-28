# UniFlow Node.js Skill Service
FROM node:20-alpine

WORKDIR /app

# Install dependencies first (for caching)
COPY package*.json ./
RUN npm ci --only=production

# Copy source code
COPY src/ ./src/

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S uniflow -u 1001 -G nodejs && \
    chown -R uniflow:nodejs /app

USER uniflow

# Environment variables
ENV NODE_ENV=production
ENV PORT=8081
ENV HOST=0.0.0.0

# Expose port
EXPOSE 8081

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8081/health || exit 1

# Start service
CMD ["node", "src/index.js"]
