import { eveChannel } from 'eve/channels/eve';
import { eveRouteAuth } from '../lib/channel-auth';

export default eveChannel({
  auth: eveRouteAuth(),
});
