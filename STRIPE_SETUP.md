# Stripe Integration Setup Guide

This document explains how to set up and configure the Stripe integration for RSS Assistant.

## Overview

The application now includes Stripe integration for handling Pro plan subscriptions with monthly billing. Users can upgrade from the Free plan to the Pro plan through a Stripe Checkout flow.

## Features

- **Stripe Checkout**: Hosted payment page for plan upgrades
- **Subscription Management**: Users can manage their subscriptions via Stripe Customer Portal
- **Webhook Integration**: Automatic sync of subscription status with Stripe events
- **Plan Enforcement**: Automatic plan changes based on subscription status

## Prerequisites

1. A Stripe account (sign up at https://stripe.com)
2. Access to Stripe Dashboard

## Setup Instructions

### 1. Create Stripe Products and Prices

1. Log in to your Stripe Dashboard
2. Go to **Products** → **Add Product**
3. Create a "Pro Plan" product:
   - Name: `Pro Plan`
   - Description: `Monthly subscription for Pro features`
   - Pricing:
     - Select "Recurring"
     - Set price: `$99.99` (or your desired price)
     - Billing period: `Monthly`
4. After creating, copy the **Price ID** (starts with `price_...`)

### 2. Get Your Stripe API Keys

1. Go to **Developers** → **API Keys**
2. Copy your:
   - **Publishable key** (starts with `pk_test_...` for test mode)
   - **Secret key** (starts with `sk_test_...` for test mode)

### 3. Set Up Webhook Endpoint

1. Go to **Developers** → **Webhooks**
2. Click **Add endpoint**
3. Enter your endpoint URL:
   - For production: `https://yourdomain.com/webhooks/stripe`
   - For development (using Stripe CLI): `http://localhost:4000/webhooks/stripe`
4. Select events to listen to:
   - `customer.subscription.created`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
   - `invoice.payment_succeeded`
   - `invoice.payment_failed`
5. After creating, copy the **Signing secret** (starts with `whsec_...`)

### 4. Configure Environment Variables

Add the following environment variables to your application:

```bash
# Stripe API Keys
STRIPE_SECRET_KEY=sk_test_xxxxxxxxxxxxx
STRIPE_PUBLIC_KEY=pk_test_xxxxxxxxxxxxx

# Stripe Price ID for Pro Plan
STRIPE_PRO_PRICE_ID=price_xxxxxxxxxxxxx

# Stripe Webhook Secret
STRIPE_WEBHOOK_SECRET=whsec_xxxxxxxxxxxxx
```

#### Development (.env)
Create a `.env` file in the root directory:

```env
STRIPE_SECRET_KEY=sk_test_xxxxxxxxxxxxx
STRIPE_PUBLIC_KEY=pk_test_xxxxxxxxxxxxx
STRIPE_PRO_PRICE_ID=price_xxxxxxxxxxxxx
STRIPE_WEBHOOK_SECRET=whsec_xxxxxxxxxxxxx
```

#### Production
Set these as environment variables in your hosting platform (e.g., Fly.io, Heroku, etc.)

### 5. Run Database Migration

Run the migration to create the subscriptions table:

```bash
mix ecto.migrate
```

### 6. Install Dependencies

Install the Stripe library:

```bash
mix deps.get
```

### 7. Test in Development (Optional)

For testing webhooks locally, use the Stripe CLI:

```bash
# Install Stripe CLI
# See: https://stripe.com/docs/stripe-cli

# Login to Stripe
stripe login

# Forward webhooks to local server
stripe listen --forward-to localhost:4000/webhooks/stripe

# Use the webhook signing secret from the CLI output in your .env
```

## Testing the Integration

### Test with Stripe Test Cards

Use these test card numbers in Stripe Checkout:

- **Success**: `4242 4242 4242 4242`
- **Decline**: `4000 0000 0000 0002`
- **Requires authentication**: `4000 0025 0000 3155`

Use any future expiry date, any 3-digit CVC, and any billing postal code.

### Test Flow

1. Start your development server: `mix phx.server`
2. Register a new user account
3. Navigate to `/billing/pricing`
4. Click "Upgrade to Pro"
5. Complete checkout using a test card
6. Verify:
   - Subscription is created in Stripe Dashboard
   - User's plan is updated in the database
   - User can access Pro features

## Available Routes

- `/billing/pricing` - View pricing plans (public)
- `/billing/checkout` - Create checkout session (authenticated)
- `/billing/success` - Success page after checkout (authenticated)
- `/billing/manage` - Manage subscription (authenticated)
- `/billing/portal` - Redirect to Stripe Customer Portal (authenticated)
- `/billing/cancel` - Cancel subscription (authenticated)
- `/billing/reactivate` - Reactivate canceled subscription (authenticated)
- `/webhooks/stripe` - Stripe webhook endpoint (public API)

## Architecture

### Database Schema

**subscriptions** table:
- `user_id` - Foreign key to users
- `plan_id` - Foreign key to plans
- `stripe_customer_id` - Stripe customer ID
- `stripe_subscription_id` - Stripe subscription ID
- `stripe_price_id` - Stripe price ID
- `status` - Subscription status (active, canceled, etc.)
- `current_period_start` - Current billing period start
- `current_period_end` - Current billing period end
- `cancel_at_period_end` - Boolean flag
- `canceled_at` - Cancellation timestamp

### Contexts

- **RssAssistant.Billing** - Handles subscription CRUD and webhook processing
- **RssAssistant.Billing.StripeService** - Stripe API client wrapper

### Controllers

- **BillingController** - Handles checkout, subscription management
- **WebhookController** - Processes Stripe webhooks

## Webhook Events

The application handles these Stripe webhook events:

- `customer.subscription.created` - Creates subscription record
- `customer.subscription.updated` - Updates subscription status
- `customer.subscription.deleted` - Marks subscription as canceled
- `invoice.payment_succeeded` - Confirms successful payment
- `invoice.payment_failed` - Handles failed payments

## Security Notes

1. **Never commit API keys** to version control
2. **Always verify webhook signatures** (already implemented)
3. **Use HTTPS in production** for webhook endpoints
4. **Keep your webhook secret secure**

## Troubleshooting

### Webhooks not working

1. Check that webhook URL is publicly accessible
2. Verify webhook signing secret is correct
3. Check application logs for webhook errors
4. Use Stripe CLI for local development testing

### Subscription not syncing

1. Check webhook events in Stripe Dashboard → Developers → Webhooks
2. Verify webhook endpoint received the event
3. Check application logs for processing errors
4. Manually trigger webhook resend from Stripe Dashboard

### User plan not updating

1. Verify webhook processed successfully
2. Check subscription status in database
3. Run `RssAssistant.Billing.sync_user_plan(subscription)` manually in IEx console

## Production Checklist

Before going to production:

- [ ] Switch to production Stripe keys (live mode)
- [ ] Update STRIPE_SECRET_KEY and STRIPE_PUBLIC_KEY
- [ ] Create production webhook endpoint
- [ ] Update STRIPE_WEBHOOK_SECRET
- [ ] Verify webhook URL is publicly accessible via HTTPS
- [ ] Test full checkout flow in production
- [ ] Test webhook events are received
- [ ] Monitor Stripe Dashboard for any issues

## Support

For Stripe-specific issues:
- Stripe Documentation: https://stripe.com/docs
- Stripe Support: https://support.stripe.com

For application issues:
- Check application logs
- Review webhook event logs in Stripe Dashboard
- Contact development team
