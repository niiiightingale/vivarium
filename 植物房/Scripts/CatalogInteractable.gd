class_name CatalogInteractable
extends StaticBody3D

signal catalog_opened

# 当玩家的 PlayerInput 射线点击到它时，调用这个函数
func interact():
	print("📖 玩家翻开了园艺邮购目录！")
	catalog_opened.emit()
