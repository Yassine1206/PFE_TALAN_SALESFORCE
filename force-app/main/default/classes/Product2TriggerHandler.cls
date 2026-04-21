public class Product2TriggerHandler {
    
    public static void handleBeforeInsert(List<Product2> newProducts) {
        validateProducts(newProducts, true);
        setAvailability(newProducts);
    }
    
    public static void handleBeforeUpdate(List<Product2> newProducts, Map<Id, Product2> oldMap) {
        validateProducts(newProducts, false);
        setAvailability(newProducts);
    }
    
    private static void validateProducts(List<Product2> products, Boolean isInsert) {
        for (Product2 p : products) {
            // Nom obligatoire — insert ET update
            if (String.isBlank(p.Name)) {
                p.addError('Le nom du produit est obligatoire.');
            }
            
            // Image obligatoire — INSERT seulement
            // Sur update, Image_URL__c peut ne pas être dans le contexte
            // (ex: decrementStock met à jour seulement Stock_Quantity__c)
            if (isInsert && String.isBlank(p.Image_URL__c)) {
                p.addError('L\'URL de l\'image est obligatoire.');
            }
            
            // Stock ne peut pas être négatif
            if (p.Stock_Quantity__c != null && p.Stock_Quantity__c < 0) {
                p.addError('Le stock ne peut pas être négatif.');
            }
            
            // Rating entre 0 et 5
            if (p.Rating__c != null && (p.Rating__c < 0 || p.Rating__c > 5)) {
                p.addError('La note doit être entre 0 et 5.');
            }
            
            // Low Stock Threshold : valeur par défaut si vide
            if (p.Low_Stock_Threshold__c == null) {
                p.Low_Stock_Threshold__c = 10;
            }
        }
    }
    
    private static void setAvailability(List<Product2> products) {
        for (Product2 p : products) {
            if (p.Availability__c != null
                && p.Availability__c != 'En arrivage'
            && p.Availability__c != 'Sur commande 48h') {
                p.Availability__c = null;
            }
        }
    }
}