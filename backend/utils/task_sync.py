import logging

logger = logging.getLogger(__name__)

TASK_SYNC_DISABLED_REASON = "task_integrations_removed_from_mvp"


async def auto_sync_action_item(uid: str, action_item: dict) -> dict:
    del uid, action_item
    logger.info("Task sync skipped: task integrations are removed in MVP mode")
    return {"synced": False, "reason": TASK_SYNC_DISABLED_REASON}


async def auto_sync_action_items_batch(uid: str, action_items: list) -> list:
    del uid
    logger.info("Batch task sync skipped: task integrations are removed in MVP mode")
    return [{"synced": False, "reason": TASK_SYNC_DISABLED_REASON} for _ in action_items]
