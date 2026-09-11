"""resources content packs

Revision ID: 9f3e1a0b2c44
Revises: c740a4ab7b61
Create Date: 2026-08-30 12:40:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.mysql import LONGBLOB


# revision identifiers, used by Alembic.
revision: str = '9f3e1a0b2c44'
down_revision: Union[str, None] = 'c740a4ab7b61'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('resources',
    sa.Column('id', sa.String(length=64), nullable=False),
    sa.Column('kind', sa.String(length=32), nullable=False),
    sa.Column('name', sa.String(length=255), nullable=False),
    sa.Column('description', sa.Text(), nullable=False),
    sa.Column('class_number', sa.Integer(), nullable=False),
    sa.Column('subject', sa.String(length=32), nullable=False),
    sa.Column('version', sa.String(length=32), nullable=False),
    sa.Column('size_bytes', sa.Integer(), nullable=False),
    sa.Column('sha256', sa.String(length=64), nullable=False),
    sa.Column('mime_type', sa.String(length=64), nullable=False),
    sa.Column('lesson_id', sa.String(length=64), nullable=True),
    sa.Column('blob', LONGBLOB().with_variant(sa.LargeBinary(), 'sqlite'), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_resources_class_number'), 'resources', ['class_number'], unique=False)
    op.create_index(op.f('ix_resources_kind'), 'resources', ['kind'], unique=False)
    op.create_index(op.f('ix_resources_lesson_id'), 'resources', ['lesson_id'], unique=False)
    op.create_index(op.f('ix_resources_subject'), 'resources', ['subject'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_resources_subject'), table_name='resources')
    op.drop_index(op.f('ix_resources_lesson_id'), table_name='resources')
    op.drop_index(op.f('ix_resources_kind'), table_name='resources')
    op.drop_index(op.f('ix_resources_class_number'), table_name='resources')
    op.drop_table('resources')