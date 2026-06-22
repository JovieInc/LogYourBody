import { WebhookEvent } from '@clerk/nextjs/server';
import { createClient } from '@supabase/supabase-js';
import { Webhook } from 'svix';

type WebhookHeaders = {
  svixId: string | null;
  svixTimestamp: string | null;
  svixSignature: string | null;
};

export type WebhookResponse = {
  body: string;
  status: number;
};

function textResponse(body: string, status: number): WebhookResponse {
  return { body, status };
}

function getSupabaseAdmin() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !key) {
    throw new Error('Missing Supabase environment variables');
  }

  return createClient(url, key, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

export async function handleClerkProfileWebhook(
  payload: unknown,
  webhookHeaders: WebhookHeaders,
): Promise<WebhookResponse> {
  const { svixId, svixTimestamp, svixSignature } = webhookHeaders;

  if (!svixId || !svixTimestamp || !svixSignature) {
    return textResponse('Error occured -- no svix headers', 400);
  }

  const body = JSON.stringify(payload);
  const webhook = new Webhook(process.env.CLERK_WEBHOOK_SECRET || '');

  let event: WebhookEvent;

  try {
    event = webhook.verify(body, {
      'svix-id': svixId,
      'svix-timestamp': svixTimestamp,
      'svix-signature': svixSignature,
    }) as WebhookEvent;
  } catch (error) {
    console.error('Error verifying webhook:', error);
    return textResponse('Error occured', 400);
  }

  const eventType = event.type;

  if (eventType === 'user.created' || eventType === 'user.updated') {
    const { id, email_addresses, first_name, last_name, image_url } = event.data;
    const primaryEmail = email_addresses.find(
      (email) => email.id === event.data.primary_email_address_id,
    );
    const email = primaryEmail?.email_address;

    const profileData = {
      id,
      email,
      name: [first_name, last_name].filter(Boolean).join(' ') || null,
      avatar_url: image_url,
      email_verified: primaryEmail?.verification?.status === 'verified',
      updated_at: new Date().toISOString(),
    };

    try {
      const supabaseAdmin = getSupabaseAdmin();
      const { error: profileError } = await supabaseAdmin.from('profiles').upsert(profileData, {
        onConflict: 'id',
      });

      if (profileError) {
        console.error('Error upserting profile:', profileError);
        return textResponse('Error creating profile', 500);
      }

      if (eventType === 'user.created') {
        const { error: subscriptionError } = await supabaseAdmin
          .from('email_subscriptions')
          .insert({
            user_id: id,
            weekly_summary: true,
            achievement_notifications: true,
            reminder_notifications: true,
            product_updates: false,
          });

        if (subscriptionError && subscriptionError.code !== '23505') {
          console.error('Error creating email subscription:', subscriptionError);
        }
      }

      console.log(`User ${eventType === 'user.created' ? 'created' : 'updated'}: ${id}`);
    } catch (error) {
      console.error('Error processing webhook:', error);
      return textResponse('Error processing webhook', 500);
    }
  }

  if (eventType === 'user.deleted') {
    const { id } = event.data;

    try {
      const supabaseAdmin = getSupabaseAdmin();
      const { error } = await supabaseAdmin.from('profiles').delete().eq('id', id);

      if (error) {
        console.error('Error deleting profile:', error);
        return textResponse('Error deleting profile', 500);
      }

      console.log(`User deleted: ${id}`);
    } catch (error) {
      console.error('Error processing webhook:', error);
      return textResponse('Error processing webhook', 500);
    }
  }

  return textResponse('', 200);
}
