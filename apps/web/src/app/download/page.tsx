import { redirect } from 'next/navigation';
export const revalidate = false;

export default function DownloadPage() {
  redirect('/download/ios');
}
