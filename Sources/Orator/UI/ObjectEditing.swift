import Foundation
import PresentationCore

extension EditorWindowController {
    func editableSlide(_ id: UUID) -> Slide? {
        if let slide=presentation.deck.slides.first(where: { $0.id == id }) { return presentation.deck.resolvedContent(slide) }
        for master in presentation.deck.masters ?? [] {
            if master.id == id { return master.slide }
            if let layout=master.layouts.first(where: { $0.id == id }) { var slide=Slide(); slide.id=layout.id; slide.title=layout.name; slide.objects=layout.objects; slide.masterID=master.id; return slide }
        }; return nil
    }
    func replacementEdit(_ slide: Slide) -> Edit? {
        if presentation.deck.slides.contains(where: { $0.id == slide.id }) { return .replaceSlide(slide) }
        guard var masters=presentation.deck.masters else { return nil }
        for i in masters.indices {
            if masters[i].id == slide.id { masters[i].objects=slide.objects; masters[i].background=slide.background; masters[i].name=slide.title; return .setMasters(masters) }
            if let j=masters[i].layouts.firstIndex(where: { $0.id == slide.id }) { masters[i].layouts[j].objects=slide.objects; masters[i].layouts[j].name=slide.title; return .setMasters(masters) }
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
