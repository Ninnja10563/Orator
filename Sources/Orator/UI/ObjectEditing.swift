import Foundation
import PresentationCore

extension EditorWindowController {
    func modifyObject(_ id: UUID,on slideID: UUID,name: String,_ change: (inout SlideObject) -> Void) {
        if var slide=presentation.deck.slides.first(where: { $0.id == slideID }), let index=slide.objects.firstIndex(where: { $0.id == id }) { change(&slide.objects[index]); presentation.perform(.replaceSlide(slide),named:name) }
        else if var masters=presentation.deck.masters, let m=masters.firstIndex(where: { $0.id == slideID }), let index=masters[m].objects.firstIndex(where: { $0.id == id }) { change(&masters[m].objects[index]); presentation.perform(.setMasters(masters),named:name) }
    }
}
