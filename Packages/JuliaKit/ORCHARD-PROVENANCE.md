Adapted from https://github.com/l22-io/orchard-mcp at 0de0967a1d298286f0101aec230ea86aaada8404.

Native adapter methods are compiled into JuliaKit. The MCP server, Node runtime and bridge executable are not included. JSON output is captured as typed Swift values; the script runner is replaced with bounded cancellable execution. Tool metadata and native dispatch were generated from the upstream CLI definitions. Julia adds input validation and ports scope/result guards. See ORCHARD-LICENSE.
