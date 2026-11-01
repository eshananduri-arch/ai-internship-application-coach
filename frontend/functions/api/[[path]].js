
export async function onRequest({ request }) {
  const backendUrl = new URL(request.url);

  backendUrl.protocol = "https:";
  backendUrl.hostname = "ai-internship-application-coach.onrender.com";

  return fetch(new Request(backendUrl, request));
}
