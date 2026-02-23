import Link from '@docusaurus/Link';
import Layout from '@theme/Layout';

export default function Home(): JSX.Element {
  return (
    <Layout title="Can Messenger Docs" description="Documentation for can_messenger">
      <main style={{ padding: '3rem 1rem', maxWidth: '920px', margin: '0 auto' }}>
        <h1>Can Messenger Documentation</h1>
        <p>
          Versioned docs are enabled. Stable docs live at <code>/docs</code> and development docs live at{' '}
          <code>/docs/next</code>.
        </p>
        <p>
          <Link to="/docs">Read stable docs (2.1.0)</Link>
        </p>
        <p>
          <Link to="/docs/next">Read next docs</Link>
        </p>
      </main>
    </Layout>
  );
}
