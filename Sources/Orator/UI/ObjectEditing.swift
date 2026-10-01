import Foundation
import PresentationCore

extension EditorWindowController {
    func editableSlide(_ id: UUID) -> Slide? {
        func find(_ slide: Slide) -> Slide? {
            if slide.id == id { return slide }
            for object in slide.objects where object.kind == .group { var nested=Slide(); nested.id=object.id; nested.title=object.name; nested.objects=object.children; if let found=find(nested) { return found } }; return nil
        }
        for slide in presentation.deck.slides { if let found=find(presentation.deck.resolvedContent(slide)) { return found } }
        for master in presentation.deck.masters ?? [] {
            if let found=find(master.slide) { return found }
            for layout in master.layouts { var slide=Slide(); slide.id=layout.id; slide.title=layout.name; slide.objects=layout.objects; slide.masterID=master.id; if let found=find(slide) { return found } }
        }; return nil
    }
    func replacementEdit(_ slide: Slide) -> Edit? {
        func replace(in objects: inout [SlideObject]) -> Bool {
            for i in objects.indices {
                if objects[i].id == slide.id && objects[i].kind == .group { objects[i].children=slide.objects; objects[i].name=slide.title; if objects[i].rotation == 0, let bounds=Geometry.bounds(slide.objects) { objects[i].frame=bounds }; return true }
                if replace(in:&objects[i].children) { return true }
            }; return false
        }
        for original in presentation.deck.slides {
            var root=original
            if root.id == slide.id { root=slide }
            else if !replace(in:&root.objects) { continue }
            let live=Set(root.objects.flatMap(\.descendantIDs)); root.animations?.removeAll { !live.contains($0.objectID) }
            return .replaceSlide(root)
        }
        guard var masters=presentation.deck.masters else { return nil }
        for i in masters.indices {
            if masters[i].id == slide.id { masters[i].objects=slide.objects; masters[i].background=slide.background; masters[i].name=slide.title; return .setMasters(masters) }
            if replace(in:&masters[i].objects) { return .setMasters(masters) }
            for j in masters[i].layouts.indices {
                if masters[i].layouts[j].id == slide.id { masters[i].layouts[j].objects=slide.objects; masters[i].layouts[j].name=slide.title; return .setMasters(masters) }
                if replace(in:&masters[i].layouts[j].objects) { return .setMasters(masters) }
            }
        }; return nil
    }
    func modifyObject(_ id: UUID,on slideID: UUID,name: String,_ change: (inout SlideObject) -> Void) {
        guard var slide=editableSlide(slideID), let index=slide.objects.firstIndex(where: { $0.id == id }) else { return }
        change(&slide.objects[index]); if let edit=replacementEdit(slide) { presentation.perform(edit,named:name) }
    }
    func insertObject(_ object: SlideObject,assets: [Asset],on slideID: UUID,name: String) {
        guard var slide=editableSlide(slideID) else { return }; slide.objects.append(object)
        guard let edit=replacementEdit(slide) else { return }
        presentation.perform(.batch(assets.map(Edit.putAsset)+[edit]),named:name)
        if currentSlide.id == slideID { canvas.selected=[object.id] }
    }
}

extension EditorWindowController {
    func editGroup(_ id: UUID) { canvas.finishText(); guard currentSlide.objects.contains(where: { $0.id == id && $0.kind == .group }) else { return }; editingGroupIDs.append(id); canvas.selected=[]; refresh() }
    @objc func editSelectedGroup(_ sender: Any?) { if let id=canvas.selected.first { editGroup(id) } }
    @objc func finishGroupEditing(_ sender: Any?) { canvas.finishText(); guard !editingGroupIDs.isEmpty else { return }; let id=editingGroupIDs.removeLast(); canvas.selected=[id]; refresh() }
}
