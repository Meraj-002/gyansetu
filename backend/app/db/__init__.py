"""Database package.

Models are registered with ``Base.metadata`` by importing ``app.models`` —
do that in the app entrypoint (``main.py``) and in Alembic's ``env.py``, not
here, to keep this package free of circular imports.
"""