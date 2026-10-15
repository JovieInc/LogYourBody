import { redirect } from 'next/navigation';
export const revalidate = false;

export default function MobilePage() {
  redirect('/download/ios');
}
