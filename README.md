# Cloud-Based Bus Pass System

## Project Overview

A serverless, cloud-native bus ticket system that prevents ticket loss, theft, and incorrect pricing while automatically scaling to handle high traffic.

**Live Demo:** [http://bus-ticket.s3-website.eu-north-1.amazonaws.com](http://bus-ticket.s3-website.eu-north-1.amazonaws.com)

---

## Features

| Feature | Implementation |
|---------|----------------|
| ✅ No ticket loss | Digital tickets stored in DynamoDB |
| ✅ No ticket theft | One-time use codes marked `used=true` after validation |
| ✅ No incorrect pricing | Price hardcoded in Lambda (backend-only) |
| ✅ Auto-scaling | Lambda + DynamoDB on-demand capacity |
| ✅ Real payments | Stripe Checkout + webhooks |

---

## Architecture Diagram

![Architecture](https://github.com/Ahmad-Hamdy-Elhendawy/Bus-System/blob/main/Architecture.png?raw=true)

