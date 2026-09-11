"""Importing this package registers every ORM model with ``Base.metadata``.

Run ``import app.models`` (or ``from app import models``) once during app
startup and in Alembic ``env.py`` before ``metadata.create_all`` /
``autogenerate``.
"""

from app.models import (  # noqa: F401
    assessment,
    classroom_session,
    learning_outcome,
    lesson,
    progress_event,
    resource,
    school,
    support_report,
    teacher,
    teacher_record,
    translation,
    worksheet,
)