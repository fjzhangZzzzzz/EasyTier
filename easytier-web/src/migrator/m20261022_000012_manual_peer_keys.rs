use sea_orm_migration::prelude::*;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        // 保留旧 URL 列及已有网络，新增字段仅用于完整保存 Manual 节点公钥。
        manager
            .get_connection()
            .execute_unprepared("ALTER TABLE networks ADD COLUMN peers TEXT NOT NULL DEFAULT '[]'")
            .await?;
        Ok(())
    }
    async fn down(&self, _manager: &SchemaManager) -> Result<(), DbErr> {
        // 静默降级会丢失 pin，回退必须恢复配套备份。
        Err(DbErr::Custom(
            "restore the matching pre-upgrade database backup to roll back peer keys".to_owned(),
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use sea_orm::{Database, Statement};

    #[tokio::test]
    async fn migration_keeps_legacy_urls_and_refuses_lossy_downgrade() {
        let db = Database::connect("sqlite::memory:").await.unwrap();
        db.execute_unprepared("CREATE TABLE networks (peer_urls TEXT NOT NULL); INSERT INTO networks VALUES ('[\"tcp://127.0.0.1:11010\"]')").await.unwrap();
        let manager = SchemaManager::new(&db);
        Migration.up(&manager).await.unwrap();
        let row = db
            .query_one(Statement::from_string(
                db.get_database_backend(),
                "SELECT peer_urls, peers FROM networks".to_owned(),
            ))
            .await
            .unwrap()
            .unwrap();
        assert_eq!(
            row.try_get::<String>("", "peer_urls").unwrap(),
            "[\"tcp://127.0.0.1:11010\"]"
        );
        assert_eq!(row.try_get::<String>("", "peers").unwrap(), "[]");
        assert!(Migration.down(&manager).await.is_err());
    }
}
